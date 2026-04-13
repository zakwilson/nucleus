// Nucleus stage-0 compiler.
//
// Reads a .nuc source file and emits textual LLVM IR to stdout.
// Throwaway scaffolding — will be replaced once Nucleus self-hosts.

#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// LLVM C API for compile-time JIT
#include <llvm-c/Core.h>
#include <llvm-c/IRReader.h>
#include <llvm-c/LLJIT.h>
#include <llvm-c/Orc.h>
#include <llvm-c/Target.h>

// ============================================================
// Arena allocator (fixed-size, no free)
// ============================================================

#define ARENA_SIZE (16u << 20)
static char  *g_arena;
static size_t g_arena_used;

static void arena_init(void) {
    g_arena = malloc(ARENA_SIZE);
    if (!g_arena) { perror("arena malloc"); exit(1); }
    g_arena_used = 0;
}

static void *arena_alloc(size_t n) {
    n = (n + 7u) & ~(size_t)7u;
    if (g_arena_used + n > ARENA_SIZE) {
        fprintf(stderr, "nucleusc: arena exhausted\n");
        exit(1);
    }
    void *p = g_arena + g_arena_used;
    g_arena_used += n;
    memset(p, 0, n);
    return p;
}

static char *arena_strndup(const char *s, size_t n) {
    char *p = arena_alloc(n + 1);
    memcpy(p, s, n);
    p[n] = 0;
    return p;
}

static char *arena_strdup(const char *s) {
    return arena_strndup(s, strlen(s));
}

static char *arena_vprintf(const char *fmt, va_list ap) {
    va_list ap2;
    va_copy(ap2, ap);
    int n = vsnprintf(NULL, 0, fmt, ap2);
    va_end(ap2);
    if (n < 0) { fprintf(stderr, "vsnprintf failed\n"); exit(1); }
    char *p = arena_alloc((size_t)n + 1);
    vsnprintf(p, (size_t)n + 1, fmt, ap);
    return p;
}

__attribute__((format(printf, 1, 2)))
static char *arena_printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    char *s = arena_vprintf(fmt, ap);
    va_end(ap);
    return s;
}

// Replace characters invalid in LLVM IR identifiers with underscores.
static char *sanitize_for_ir(const char *name) {
    size_t n = strlen(name);
    char  *s = arena_alloc(n + 1);
    for (size_t i = 0; i < n; i++)
        s[i] = (isalnum((unsigned char)name[i]) || name[i] == '_' || name[i] == '.') ? name[i] : '_';
    s[n] = '\0';
    return s;
}

// ============================================================
// Error reporting
// ============================================================

static const char *g_source_path = "<input>";

__attribute__((noreturn, format(printf, 2, 3)))
static void die_at(int line, const char *fmt, ...) {
    fprintf(stderr, "%s:%d: error: ", g_source_path, line);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

// ============================================================
// Lexer
// ============================================================

typedef enum {
    TOK_LPAREN,
    TOK_RPAREN,
    TOK_QUOTE,
    TOK_QUASI,
    TOK_UNQUOTE,
    TOK_UNQUOTE_SPLICE,
    TOK_INT,
    TOK_STRING,
    TOK_SYMBOL,
    TOK_EOF,
} TokKind;

typedef struct {
    TokKind kind;
    int     line;
    long    i;   // TOK_INT
    char   *s;   // TOK_STRING (decoded), TOK_SYMBOL
} Tok;

static const char *g_src;
static size_t      g_pos;
static int         g_line;

static void lex_init(const char *src) {
    g_src = src;
    g_pos = 0;
    g_line = 1;
}

static int peek_char(void) { return (unsigned char)g_src[g_pos]; }

static int next_char(void) {
    int c = peek_char();
    if (c == 0) return 0;
    g_pos++;
    if (c == '\n') g_line++;
    return c;
}

static void skip_ws(void) {
    for (;;) {
        int c = peek_char();
        if (c == 0) return;
        if (isspace(c)) { next_char(); continue; }
        if (c == ';') {
            while (peek_char() != 0 && peek_char() != '\n') next_char();
            continue;
        }
        return;
    }
}

static bool is_sym_char(int c) {
    if (c == 0 || isspace(c)) return false;
    if (c == '(' || c == ')' || c == '"' || c == ';') return false;
    return true;
}

static Tok lex_string(int open_line) {
    // opening quote already consumed
    char buf[4096];
    size_t n = 0;
    for (;;) {
        int c = next_char();
        if (c == 0) die_at(open_line, "unterminated string literal");
        if (c == '"') break;
        if (c == '\\') {
            int e = next_char();
            switch (e) {
                case 'n':  c = '\n'; break;
                case 't':  c = '\t'; break;
                case 'r':  c = '\r'; break;
                case '0':  c = '\0'; break;
                case '\\': c = '\\'; break;
                case '"':  c = '"';  break;
                default:
                    die_at(g_line, "unknown escape \\%c", e);
            }
        }
        if (n + 1 >= sizeof(buf)) die_at(open_line, "string literal too long");
        buf[n++] = (char)c;
    }
    Tok t = { .kind = TOK_STRING, .line = open_line, .s = arena_strndup(buf, n) };
    return t;
}

static Tok lex_atom(void) {
    int start_line = g_line;
    size_t start = g_pos;
    while (is_sym_char(peek_char())) next_char();
    size_t len = g_pos - start;
    const char *text = g_src + start;

    // Integer? Optional leading -/+, then digits only.
    bool is_int = (len > 0);
    size_t i0 = 0;
    if (len > 0 && (text[0] == '-' || text[0] == '+')) i0 = 1;
    if (i0 == len) is_int = false;
    for (size_t i = i0; i < len; i++) {
        if (!isdigit((unsigned char)text[i])) { is_int = false; break; }
    }
    if (is_int) {
        char buf[64];
        if (len >= sizeof(buf)) die_at(start_line, "integer literal too long");
        memcpy(buf, text, len);
        buf[len] = 0;
        Tok t = { .kind = TOK_INT, .line = start_line, .i = strtol(buf, NULL, 10) };
        return t;
    }
    Tok t = { .kind = TOK_SYMBOL, .line = start_line, .s = arena_strndup(text, len) };
    return t;
}

static Tok next_tok(void) {
    skip_ws();
    int c = peek_char();
    int line = g_line;
    if (c == 0) { Tok t = { .kind = TOK_EOF, .line = line }; return t; }
    if (c == '(') { next_char(); Tok t = { .kind = TOK_LPAREN, .line = line }; return t; }
    if (c == ')') { next_char(); Tok t = { .kind = TOK_RPAREN, .line = line }; return t; }
    if (c == '\'') { next_char(); Tok t = { .kind = TOK_QUOTE, .line = line }; return t; }
    if (c == '`')  { next_char(); Tok t = { .kind = TOK_QUASI, .line = line }; return t; }
    if (c == '~') {
        next_char();
        if (peek_char() == '@') {
            next_char();
            Tok t = { .kind = TOK_UNQUOTE_SPLICE, .line = line };
            return t;
        }
        Tok t = { .kind = TOK_UNQUOTE, .line = line };
        return t;
    }
    if (c == '"') { next_char(); return lex_string(line); }
    return lex_atom();
}

// ============================================================
// Reader / AST
// ============================================================

typedef enum {
    NODE_INT,
    NODE_STR,
    NODE_SYM,
    NODE_CELL,
} NodeKind;

// Node layout must match the Nucleus defstruct Node { kind:i32 line:i32 i:i64 s:ptr car:ptr cdr:ptr }
// i.e. { i32, i32, i64, ptr, ptr, ptr } = 40 bytes.  This is required so that nodes created by
// JIT-compiled macro functions (using the LLVM struct layout) can be read back by the C bootstrap.
typedef struct Node {
    NodeKind       kind;  // offset  0
    int            line;  // offset  4
    long           i;     // offset  8  (NODE_INT)
    char          *s;     // offset 16  (NODE_STR, NODE_SYM)
    struct Node   *car;   // offset 24  (NODE_CELL)
    struct Node   *cdr;   // offset 32  (NODE_CELL, cdr=NULL terminates)
} Node;

// A list is a chain of NODE_CELL nodes terminated by NULL. The empty list is NULL.
static int node_len(Node *n) {
    int k = 0;
    while (n && n->kind == NODE_CELL) { k++; n = n->cdr; }
    return k;
}

static Node *node_at(Node *n, int i) {
    while (n && n->kind == NODE_CELL && i > 0) { n = n->cdr; i--; }
    return (n && n->kind == NODE_CELL) ? n->car : NULL;
}

static bool node_is_list(Node *n) {
    return n == NULL || n->kind == NODE_CELL;
}

static Tok  g_peek;
static bool g_peek_valid;

static Tok peek_tok(void) {
    if (!g_peek_valid) { g_peek = next_tok(); g_peek_valid = true; }
    return g_peek;
}

static Tok eat_tok(void) {
    Tok t = peek_tok();
    g_peek_valid = false;
    return t;
}

static Node *read_form(void);

static Node *make_cell(Node *car, Node *cdr, int line) {
    Node *c = arena_alloc(sizeof(Node));
    c->kind = NODE_CELL;
    c->line = line;
    c->car = car;
    c->cdr = cdr;
    return c;
}

static Node *read_list(int line) {
    Node *head = NULL, *tail = NULL;
    for (;;) {
        Tok t = peek_tok();
        if (t.kind == TOK_EOF) die_at(line, "unterminated list");
        if (t.kind == TOK_RPAREN) { eat_tok(); break; }
        Node *child = read_form();
        Node *cell = make_cell(child, NULL, line);
        if (tail) tail->cdr = cell; else head = cell;
        tail = cell;
    }
    return head;
}

static Node *read_form(void) {
    Tok t = eat_tok();
    Node *n;
    switch (t.kind) {
        case TOK_LPAREN: return read_list(t.line);
        case TOK_RPAREN: die_at(t.line, "unexpected )");
        case TOK_QUOTE:
        case TOK_QUASI:
        case TOK_UNQUOTE:
        case TOK_UNQUOTE_SPLICE: {
            const char *op = t.kind == TOK_QUOTE ? "quote"
                           : t.kind == TOK_QUASI ? "quasiquote"
                           : t.kind == TOK_UNQUOTE ? "unquote"
                           : "unquote-splice";
            Node *quoted = read_form();
            Node *sym = arena_alloc(sizeof(Node));
            sym->kind = NODE_SYM; sym->line = t.line; sym->s = arena_strndup(op, (int)strlen(op));
            return make_cell(sym, make_cell(quoted, NULL, t.line), t.line);
        }
        case TOK_INT:
            n = arena_alloc(sizeof(Node));
            n->kind = NODE_INT; n->line = t.line; n->i = t.i;
            return n;
        case TOK_STRING:
            n = arena_alloc(sizeof(Node));
            n->kind = NODE_STR; n->line = t.line; n->s = t.s;
            return n;
        case TOK_SYMBOL:
            n = arena_alloc(sizeof(Node));
            n->kind = NODE_SYM; n->line = t.line; n->s = t.s;
            return n;
        case TOK_EOF:
            die_at(t.line, "unexpected end of input");
    }
    return NULL;
}

static Node *read_program(void) {
    Node *head = NULL, *tail = NULL;
    while (peek_tok().kind != TOK_EOF) {
        Node *form = read_form();
        Node *cell = make_cell(form, NULL, form ? form->line : 0);
        if (tail) tail->cdr = cell; else head = cell;
        tail = cell;
    }
    return head;
}

// ============================================================
// Types
// ============================================================

typedef enum {
    TY_VOID,
    TY_I1,
    TY_I8,
    TY_I16,
    TY_I32,
    TY_I64,
    TY_PTR,
    TY_FN,
    TY_STRUCT,
} TypeKind;

typedef struct Type Type;
typedef struct StructDef {
    const char  *name;
    char       **field_names;
    Type       **field_types;
    int          num_fields;
} StructDef;

struct Type {
    TypeKind       kind;
    struct Type   *ret;
    struct Type  **params;
    int            num_params;
    bool           variadic;
    struct Type   *elem;   // TY_PTR pointee (NULL for untyped `ptr`)
    StructDef     *sdef;   // TY_STRUCT definition
};

static Type *ty_void, *ty_i1, *ty_i8, *ty_i16, *ty_i32, *ty_i64, *ty_ptr;

#define MAX_STRUCTS 64
static StructDef g_structs[MAX_STRUCTS];
static int g_structs_len;

static StructDef *register_struct(const char *name) {
    if (g_structs_len >= MAX_STRUCTS) {
        fprintf(stderr, "nucleusc: too many structs\n");
        exit(1);
    }
    StructDef *sd = &g_structs[g_structs_len++];
    sd->name = name;
    return sd;
}

static StructDef *lookup_struct(const char *name) {
    for (int i = 0; i < g_structs_len; i++) {
        if (strcmp(g_structs[i].name, name) == 0) return &g_structs[i];
    }
    return NULL;
}

static Type *make_type(TypeKind k) {
    Type *t = arena_alloc(sizeof(Type));
    t->kind = k;
    return t;
}

static void types_init(void) {
    ty_void = make_type(TY_VOID);
    ty_i1   = make_type(TY_I1);
    ty_i8   = make_type(TY_I8);
    ty_i16  = make_type(TY_I16);
    ty_i32  = make_type(TY_I32);
    ty_i64  = make_type(TY_I64);
    ty_ptr  = make_type(TY_PTR);
}

static const char *type_to_ir(Type *t) {
    switch (t->kind) {
        case TY_VOID:   return "void";
        case TY_I1:     return "i1";
        case TY_I8:     return "i8";
        case TY_I16:    return "i16";
        case TY_I32:    return "i32";
        case TY_I64:    return "i64";
        case TY_PTR:    return "ptr";
        case TY_FN:     return "<fn>";
        case TY_STRUCT: return arena_printf("%%%s", t->sdef->name);
    }
    return "?";
}

static bool is_int_type(Type *t) {
    switch (t->kind) {
        case TY_I1: case TY_I8: case TY_I16: case TY_I32: case TY_I64:
            return true;
        default:
            return false;
    }
}

// Natural alignment in bytes for primitive types. Used in alloca/load/store.
static int type_align(Type *t) {
    switch (t->kind) {
        case TY_I1:  return 1;
        case TY_I8:  return 1;
        case TY_I16: return 2;
        case TY_I32: return 4;
        case TY_I64: return 8;
        case TY_PTR:    return 8;
        case TY_STRUCT: return 8;
        default:        return 1;
    }
}

static Type *parse_type_name(const char *name, int line) {
    if (name[0] == '*') {
        Type *inner = parse_type_name(name + 1, line);
        Type *p = make_type(TY_PTR);
        p->elem = inner;
        return p;
    }
    if (strcmp(name, "int")  == 0) return ty_i32;
    if (strcmp(name, "i1")   == 0) return ty_i1;
    if (strcmp(name, "i8")   == 0) return ty_i8;
    if (strcmp(name, "i16")  == 0) return ty_i16;
    if (strcmp(name, "i32")  == 0) return ty_i32;
    if (strcmp(name, "i64")  == 0) return ty_i64;
    if (strcmp(name, "bool") == 0) return ty_i1;
    if (strcmp(name, "ptr")  == 0) return ty_ptr;
    if (strcmp(name, "void") == 0) return ty_void;
    StructDef *sd = lookup_struct(name);
    if (sd) {
        Type *t = make_type(TY_STRUCT);
        t->sdef = sd;
        return t;
    }
    die_at(line, "unknown type: %s", name);
}

// Split "name:type" into name and optional type. If no colon, *out_type_name = NULL.
static void split_typed(const char *sym, char **out_name, char **out_type_name) {
    const char *colon = strchr(sym, ':');
    if (!colon) {
        *out_name = arena_strdup(sym);
        *out_type_name = NULL;
        return;
    }
    *out_name = arena_strndup(sym, (size_t)(colon - sym));
    *out_type_name = arena_strdup(colon + 1);
}

// ============================================================
// Symbol table
// ============================================================

typedef struct Sym {
    const char *name;
    Type       *type;
    const char *ir_name;    // "%i.addr" for locals, "@printf" for globals
    bool        is_local;
    bool        is_const;
    const char *const_val;  // literal value for compile-time constants
} Sym;

typedef struct Scope {
    struct Scope *parent;
    Sym          *syms;
    int           len, cap;
} Scope;

// ============================================================
// Macro registry
// ============================================================

typedef struct {
    const char *name;      // Nucleus symbol name (e.g. "my-macro")
    const char *jit_name;  // JIT function name   (e.g. "__macro_my-macro")
    int         num_params;
} MacroDef;

#define MAX_MACROS 256
static MacroDef g_macros[MAX_MACROS];
static int      g_num_macros = 0;
static int      g_gensym_id  = 0;

// nucleus_gensym — exported (not static) so JIT macro bodies can call it
// via LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess.
Node *nucleus_gensym(void) {
    char *buf = malloc(32);
    if (!buf) { perror("malloc"); exit(1); }
    snprintf(buf, 32, "__gs_%d", g_gensym_id++);
    Node *n = calloc(1, sizeof(Node));
    if (!n) { perror("calloc"); exit(1); }
    n->kind = NODE_SYM;
    n->s    = buf;
    return n;
}

static Scope *scope_new(Scope *parent) {
    Scope *s = arena_alloc(sizeof(Scope));
    s->parent = parent;
    return s;
}

static Sym *scope_define(Scope *s, const char *name, Type *type,
                         const char *ir_name, bool is_local) {
    if (s->len == s->cap) {
        int nc = s->cap ? s->cap * 2 : 8;
        Sym *ns = arena_alloc((size_t)nc * sizeof(Sym));
        for (int i = 0; i < s->len; i++) ns[i] = s->syms[i];
        s->syms = ns;
        s->cap = nc;
    }
    Sym *sym = &s->syms[s->len++];
    sym->name = name;
    sym->type = type;
    sym->ir_name = ir_name;
    sym->is_local = is_local;
    return sym;
}

static Sym *scope_lookup(Scope *s, const char *name) {
    for (Scope *c = s; c; c = c->parent) {
        for (int i = c->len - 1; i >= 0; i--) {
            if (strcmp(c->syms[i].name, name) == 0) return &c->syms[i];
        }
    }
    return NULL;
}

// ============================================================
// Module-level string literal table
// ============================================================

typedef struct {
    char *bytes;  // decoded payload
    int   len;    // bytes (excluding the NUL we will emit)
    int   id;
} StrLit;

static StrLit *g_strs;
static int     g_strs_len;
static int     g_strs_cap;

static int intern_string(const char *bytes, int len) {
    int id = g_strs_len;
    if (g_strs_len == g_strs_cap) {
        int nc = g_strs_cap ? g_strs_cap * 2 : 8;
        StrLit *ns = malloc((size_t)nc * sizeof(StrLit));
        if (!ns) { perror("malloc"); exit(1); }
        if (g_strs) {
            memcpy(ns, g_strs, (size_t)g_strs_len * sizeof(StrLit));
            free(g_strs);
        }
        g_strs = ns;
        g_strs_cap = nc;
    }
    g_strs[g_strs_len].bytes = arena_strndup(bytes, (size_t)len);
    g_strs[g_strs_len].len = len;
    g_strs[g_strs_len].id = id;
    g_strs_len++;
    return id;
}

// ============================================================
// Codegen
// ============================================================

typedef struct {
    Type       *type;
    const char *val;
} Val;

static FILE  *g_out;      // current emit destination for top-level (declares or defines stream)
static FILE  *g_decl_out; // decl stream, used for quote globals
static Scope *g_globals;
static int    g_quote_id;
static bool   g_qq_used;  // quasiquote helpers needed
static int    g_ct_id;    // counter for unique compile-time module names

// Main module streams — promoted from main() so emit_compile_time can access them.
static FILE  *g_type_stream;
static FILE  *g_decl_stream; // same FILE* as g_decl_out
static FILE  *g_def_stream;
static char  *g_type_buf;    // updated by open_memstream / fflush
static char  *g_decl_buf;
static char  *g_def_buf;
static size_t g_type_sz;
static size_t g_decl_sz;
static size_t g_def_sz;

// Compile-time JIT state (LLVM ORC LLJIT)
static LLVMOrcLLJITRef    g_jit;
static LLVMOrcJITDylibRef g_jit_dylib;

// Per-function state
static int    g_tmp;
static int    g_label;
static char  *g_entry_buf;
static size_t g_entry_len, g_entry_cap;
static char  *g_body_buf;
static size_t g_body_len,  g_body_cap;
static bool   g_block_term;

static void buf_append(char **buf, size_t *len, size_t *cap,
                       const char *s, size_t n) {
    if (*len + n + 1 > *cap) {
        size_t nc = *cap ? *cap * 2 : 1024;
        while (nc < *len + n + 1) nc *= 2;
        char *nb = malloc(nc);
        if (!nb) { perror("malloc"); exit(1); }
        if (*buf) { memcpy(nb, *buf, *len); free(*buf); }
        *buf = nb;
        *cap = nc;
    }
    memcpy(*buf + *len, s, n);
    *len += n;
    (*buf)[*len] = 0;
}

__attribute__((format(printf, 1, 2)))
static void entry_emit(const char *fmt, ...) {
    va_list ap, ap2;
    va_start(ap, fmt);
    va_copy(ap2, ap);
    int n = vsnprintf(NULL, 0, fmt, ap2);
    va_end(ap2);
    char *tmp = malloc((size_t)n + 1);
    if (!tmp) { perror("malloc"); exit(1); }
    vsnprintf(tmp, (size_t)n + 1, fmt, ap);
    va_end(ap);
    buf_append(&g_entry_buf, &g_entry_len, &g_entry_cap, tmp, (size_t)n);
    free(tmp);
}

__attribute__((format(printf, 1, 2)))
static void body_emit(const char *fmt, ...) {
    va_list ap, ap2;
    va_start(ap, fmt);
    va_copy(ap2, ap);
    int n = vsnprintf(NULL, 0, fmt, ap2);
    va_end(ap2);
    char *tmp = malloc((size_t)n + 1);
    if (!tmp) { perror("malloc"); exit(1); }
    vsnprintf(tmp, (size_t)n + 1, fmt, ap);
    va_end(ap);
    buf_append(&g_body_buf, &g_body_len, &g_body_cap, tmp, (size_t)n);
    free(tmp);
}

static const char *new_tmp(void) {
    return arena_printf("%%t%d", g_tmp++);
}

static int new_label_id(void) {
    return g_label++;
}

static void reset_function_state(void) {
    g_tmp = 0;
    g_label = 0;
    if (g_entry_buf) g_entry_buf[0] = 0;
    g_entry_len = 0;
    if (g_body_buf) g_body_buf[0] = 0;
    g_body_len = 0;
    g_block_term = false;
}

// ------------------------------------------------------------
// Expression codegen
// ------------------------------------------------------------

static Val emit_node(Node *n, Scope *scope);
static Val emit_macro_call(Node *call, Scope *scope, int macro_idx);

static Val emit_int(Node *n) {
    Val v = { ty_i32, arena_printf("%ld", n->i) };
    return v;
}

// Emits Node-typed global constants for a quoted form tree.
// Returns an LLVM-IR reference (global name or "null") pointing to the root.
static const char *emit_quote_tree(Node *n) {
    if (n == NULL) return "null";
    if (n->kind == NODE_INT) {
        int id = g_quote_id++;
        fprintf(g_decl_out,
                "@.q%d = private unnamed_addr constant "
                "{ i32, i32, i64, ptr, ptr, ptr } "
                "{ i32 0, i32 %d, i64 %ld, ptr null, ptr null, ptr null }, align 8\n",
                id, n->line, n->i);
        return arena_printf("@.q%d", id);
    }
    if (n->kind == NODE_STR || n->kind == NODE_SYM) {
        int kind = (n->kind == NODE_STR) ? 1 : 2;
        int sid = intern_string(n->s, (int)strlen(n->s));
        int ir_len = g_strs[sid].len + 1;
        int id = g_quote_id++;
        fprintf(g_decl_out,
                "@.q%d = private unnamed_addr constant "
                "{ i32, i32, i64, ptr, ptr, ptr } "
                "{ i32 %d, i32 %d, i64 0, "
                "ptr getelementptr inbounds ([%d x i8], ptr @.str.%d, i64 0, i64 0), "
                "ptr null, ptr null }, align 8\n",
                id, kind, n->line, ir_len, sid);
        return arena_printf("@.q%d", id);
    }
    // NODE_CELL: emit children first, then self
    const char *car_ref = emit_quote_tree(n->car);
    const char *cdr_ref = emit_quote_tree(n->cdr);
    int id = g_quote_id++;
    fprintf(g_decl_out,
            "@.q%d = private unnamed_addr constant "
            "{ i32, i32, i64, ptr, ptr, ptr } "
            "{ i32 3, i32 %d, i64 0, ptr null, ptr %s, ptr %s }, align 8\n",
            id, n->line, car_ref, cdr_ref);
    return arena_printf("@.q%d", id);
}

static Val emit_quote(Node *call) {
    if (node_len(call) != 2) die_at(call->line, "quote: expects 1 arg");
    const char *ref = emit_quote_tree(node_at(call, 1));
    Val v = { ty_ptr, ref };
    return v;
}

static Val emit_qq_form(Node *form, Scope *scope);

static bool is_tagged(Node *n, const char *tag) {
    if (!n || n->kind != NODE_CELL || node_len(n) != 2) return false;
    Node *h = n->car;
    return h && h->kind == NODE_SYM && strcmp(h->s, tag) == 0;
}

static Val emit_qq_list(Node *list, Scope *scope) {
    if (list == NULL) { Val v = { ty_ptr, "null" }; return v; }
    Node *elem = list->car;
    g_qq_used = true;
    if (is_tagged(elem, "unquote-splice")) {
        Val a = emit_node(node_at(elem, 1), scope);
        Val rest = emit_qq_list(list->cdr, scope);
        const char *tmp = new_tmp();
        body_emit("  %s = call ptr @__append(ptr %s, ptr %s)\n",
                  tmp, a.val, rest.val);
        Val v = { ty_ptr, tmp }; return v;
    }
    Val head = emit_qq_form(elem, scope);
    Val tail = emit_qq_list(list->cdr, scope);
    const char *tmp = new_tmp();
    body_emit("  %s = call ptr @__cons(ptr %s, ptr %s)\n",
              tmp, head.val, tail.val);
    Val v = { ty_ptr, tmp }; return v;
}

static Val emit_qq_form(Node *form, Scope *scope) {
    if (form == NULL) { Val v = { ty_ptr, "null" }; return v; }
    if (form->kind != NODE_CELL) {
        const char *ref = emit_quote_tree(form);
        Val v = { ty_ptr, ref }; return v;
    }
    if (is_tagged(form, "unquote")) {
        return emit_node(node_at(form, 1), scope);
    }
    if (is_tagged(form, "unquote-splice")) {
        die_at(form->line, "unquote-splice outside list");
    }
    return emit_qq_list(form, scope);
}

static Val emit_quasiquote(Node *call, Scope *scope) {
    if (node_len(call) != 2) die_at(call->line, "quasiquote: expects 1 arg");
    return emit_qq_form(node_at(call, 1), scope);
}

static Val emit_string(Node *n) {
    int id = intern_string(n->s, (int)strlen(n->s));
    int ir_len = g_strs[id].len + 1; // + NUL terminator
    const char *tmp = new_tmp();
    body_emit("  %s = getelementptr inbounds [%d x i8], ptr @.str.%d, i64 0, i64 0\n",
              tmp, ir_len, id);
    Val v = { ty_ptr, tmp };
    return v;
}

static Val emit_symbol_ref(Node *n, Scope *scope) {
    if (strcmp(n->s, "null") == 0)  { Val v = { ty_ptr, "null" }; return v; }
    if (strcmp(n->s, "true") == 0)  { Val v = { ty_i1,  "1" };    return v; }
    if (strcmp(n->s, "false") == 0) { Val v = { ty_i1,  "0" };    return v; }
    Sym *sym = scope_lookup(scope, n->s);
    if (!sym) die_at(n->line, "undefined: %s", n->s);
    if (sym->is_const) {
        Val v = { sym->type, sym->const_val };
        return v;
    }
    if (!sym->is_local) die_at(n->line, "cannot use function '%s' as value", n->s);
    const char *tmp = new_tmp();
    body_emit("  %s = load %s, ptr %s, align %d\n",
              tmp, type_to_ir(sym->type), sym->ir_name, type_align(sym->type));
    Val v = { sym->type, tmp };
    return v;
}

// Binary integer operators (arithmetic, bitwise, comparison). `is_cmp` means
// the instruction is `icmp <pred>` and the result type is i1.
typedef struct {
    const char *name;
    const char *instr;
    bool        is_cmp;
} BinOp;

static const BinOp g_binops[] = {
    { "+",       "add nsw",  false },
    { "-",       "sub nsw",  false },
    { "*",       "mul nsw",  false },
    { "/",       "sdiv",     false },
    { "%",       "srem",     false },
    { "bit-and", "and",      false },
    { "bit-or",  "or",       false },
    { "bit-xor", "xor",      false },
    { "bit-shl", "shl",      false },
    { "bit-shr", "ashr",     false },
    { "=",       "icmp eq",  true  },
    { "!=",      "icmp ne",  true  },
    { "<",       "icmp slt", true  },
    { "<=",      "icmp sle", true  },
    { ">",       "icmp sgt", true  },
    { ">=",      "icmp sge", true  },
};

static const BinOp *lookup_binop(const char *name) {
    for (size_t i = 0; i < sizeof(g_binops) / sizeof(g_binops[0]); i++) {
        if (strcmp(g_binops[i].name, name) == 0) return &g_binops[i];
    }
    return NULL;
}

static Val emit_binop(Node *call, Scope *scope, const BinOp *op) {
    if (node_len(call) != 3)
        die_at(call->line, "%s expects 2 args", op->name);
    Val a = emit_node(node_at(call, 1), scope);
    Val b = emit_node(node_at(call, 2), scope);
    if (a.type->kind == TY_PTR && b.type->kind == TY_PTR && op->is_cmp) {
        const char *tmp = new_tmp();
        body_emit("  %s = %s ptr %s, %s\n", tmp, op->instr, a.val, b.val);
        Val v = { ty_i1, tmp };
        return v;
    }
    if (!is_int_type(a.type) || !is_int_type(b.type))
        die_at(call->line, "%s expects integer operands", op->name);
    if (a.type->kind != b.type->kind)
        die_at(call->line, "%s operand type mismatch", op->name);
    const char *tmp = new_tmp();
    body_emit("  %s = %s %s %s, %s\n",
              tmp, op->instr, type_to_ir(a.type), a.val, b.val);
    Val v = { op->is_cmp ? ty_i1 : a.type, tmp };
    return v;
}

// (cast TargetType expr) — explicit integer/pointer conversion.
static int int_width(Type *t) {
    switch (t->kind) {
        case TY_I1:  return 1;
        case TY_I8:  return 8;
        case TY_I16: return 16;
        case TY_I32: return 32;
        case TY_I64: return 64;
        default:     return 0;
    }
}

static Val emit_cast(Node *call, Scope *scope) {
    if (node_len(call) != 3) die_at(call->line, "cast expects 2 args");
    Node *type_node = node_at(call, 1);
    if (type_node->kind != NODE_SYM)
        die_at(type_node->line, "cast: target type must be a symbol");
    Type *dst = parse_type_name(type_node->s, type_node->line);
    Val v = emit_node(node_at(call, 2), scope);
    Type *src = v.type;

    if (src->kind == dst->kind) { Val r = { dst, v.val }; return r; }

    const char *instr = NULL;
    if (is_int_type(src) && is_int_type(dst)) {
        int sw = int_width(src), dw = int_width(dst);
        instr = (dw < sw) ? "trunc" : "sext";
    } else if (is_int_type(src) && dst->kind == TY_PTR) {
        instr = "inttoptr";
    } else if (src->kind == TY_PTR && is_int_type(dst)) {
        instr = "ptrtoint";
    } else {
        die_at(call->line, "cast: unsupported conversion");
    }
    const char *tmp = new_tmp();
    body_emit("  %s = %s %s %s to %s\n",
              tmp, instr, type_to_ir(src), v.val, type_to_ir(dst));
    Val r = { dst, tmp };
    return r;
}

// (. ptr field) — struct field access via pointer
static Val emit_field_get(Node *call, Scope *scope) {
    if (node_len(call) != 3) die_at(call->line, ". expects 2 args");
    Val p = emit_node(node_at(call, 1), scope);
    if (p.type->kind != TY_PTR || !p.type->elem ||
        p.type->elem->kind != TY_STRUCT)
        die_at(call->line, ".: operand must be pointer to struct");
    Node *fn = node_at(call, 2);
    if (fn->kind != NODE_SYM) die_at(fn->line, ".: field name must be symbol");
    StructDef *sd = p.type->elem->sdef;
    int idx = -1;
    for (int i = 0; i < sd->num_fields; i++) {
        if (strcmp(sd->field_names[i], fn->s) == 0) { idx = i; break; }
    }
    if (idx < 0) die_at(fn->line, ".: no field '%s' on struct '%s'",
                        fn->s, sd->name);
    Type *ftype = sd->field_types[idx];
    const char *gep = new_tmp();
    body_emit("  %s = getelementptr inbounds %%%s, ptr %s, i32 0, i32 %d\n",
              gep, sd->name, p.val, idx);
    const char *val = new_tmp();
    body_emit("  %s = load %s, ptr %s, align %d\n",
              val, type_to_ir(ftype), gep, type_align(ftype));
    Val r = { ftype, val };
    return r;
}

// (.set! ptr field value) — struct field set via pointer
static Val emit_field_set(Node *call, Scope *scope) {
    if (node_len(call) != 4) die_at(call->line, ".set! expects 3 args");
    Val p = emit_node(node_at(call, 1), scope);
    if (p.type->kind != TY_PTR || !p.type->elem ||
        p.type->elem->kind != TY_STRUCT)
        die_at(call->line, ".set!: operand must be pointer to struct");
    Node *fn = node_at(call, 2);
    if (fn->kind != NODE_SYM) die_at(fn->line, ".set!: field name must be symbol");
    StructDef *sd = p.type->elem->sdef;
    int idx = -1;
    for (int i = 0; i < sd->num_fields; i++) {
        if (strcmp(sd->field_names[i], fn->s) == 0) { idx = i; break; }
    }
    if (idx < 0) die_at(fn->line, ".set!: no field '%s' on struct '%s'",
                        fn->s, sd->name);
    Type *ftype = sd->field_types[idx];
    Val v = emit_node(node_at(call, 3), scope);
    if (v.type->kind != ftype->kind)
        die_at(call->line, ".set!: type mismatch for field '%s'", fn->s);
    const char *gep = new_tmp();
    body_emit("  %s = getelementptr inbounds %%%s, ptr %s, i32 0, i32 %d\n",
              gep, sd->name, p.val, idx);
    body_emit("  store %s %s, ptr %s, align %d\n",
              type_to_ir(ftype), v.val, gep, type_align(ftype));
    Val r = { ty_void, NULL };
    return r;
}

// (sizeof TypeName) — size of a type at runtime via GEP trick
static Val emit_sizeof(Node *call, Scope *scope) {
    (void)scope;
    if (node_len(call) != 2) die_at(call->line, "sizeof expects 1 arg");
    Node *tn = node_at(call, 1);
    if (tn->kind != NODE_SYM) die_at(tn->line, "sizeof: arg must be type name");
    Type *ty = parse_type_name(tn->s, tn->line);
    const char *gep = new_tmp();
    body_emit("  %s = getelementptr %s, ptr null, i32 1\n",
              gep, type_to_ir(ty));
    const char *sz = new_tmp();
    body_emit("  %s = ptrtoint ptr %s to i64\n", sz, gep);
    Val r = { ty_i64, sz };
    return r;
}

// (alloca T) or (alloca T N) — stack-allocate and return typed pointer
static Val emit_alloca_form(Node *call, Scope *scope) {
    if (node_len(call) != 2 && node_len(call) != 3)
        die_at(call->line, "alloca expects 1 or 2 args");
    Node *tn = node_at(call, 1);
    if (tn->kind != NODE_SYM) die_at(tn->line, "alloca: first arg must be type name");
    Type *ty = parse_type_name(tn->s, tn->line);
    const char *slot = new_tmp();
    if (node_len(call) == 3) {
        Val n = emit_node(node_at(call, 2), scope);
        body_emit("  %s = alloca %s, i32 %s, align %d\n",
                  slot, type_to_ir(ty), n.val, type_align(ty));
    } else {
        entry_emit("  %s = alloca %s, align %d\n",
                   slot, type_to_ir(ty), type_align(ty));
    }
    Type *pt = make_type(TY_PTR);
    pt->elem = ty;
    Val r = { pt, slot };
    return r;
}

// (aref p i) — indexed element load
static Val emit_aref(Node *call, Scope *scope) {
    if (node_len(call) != 3) die_at(call->line, "aref expects 2 args");
    Val p = emit_node(node_at(call, 1), scope);
    if (p.type->kind != TY_PTR || !p.type->elem)
        die_at(call->line, "aref: operand must be typed pointer");
    Val idx = emit_node(node_at(call, 2), scope);
    if (!is_int_type(idx.type))
        die_at(call->line, "aref: index must be integer");
    const char *idx64 = idx.val;
    if (idx.type->kind != TY_I64) {
        const char *t = new_tmp();
        body_emit("  %s = sext %s %s to i64\n",
                  t, type_to_ir(idx.type), idx.val);
        idx64 = t;
    }
    Type *elem = p.type->elem;
    const char *gep = new_tmp();
    body_emit("  %s = getelementptr inbounds %s, ptr %s, i64 %s\n",
              gep, type_to_ir(elem), p.val, idx64);
    const char *val = new_tmp();
    body_emit("  %s = load %s, ptr %s, align %d\n",
              val, type_to_ir(elem), gep, type_align(elem));
    Val r = { elem, val };
    return r;
}

// (aset! p i v) — indexed element store
static Val emit_aset(Node *call, Scope *scope) {
    if (node_len(call) != 4) die_at(call->line, "aset! expects 3 args");
    Val p = emit_node(node_at(call, 1), scope);
    if (p.type->kind != TY_PTR || !p.type->elem)
        die_at(call->line, "aset!: operand must be typed pointer");
    Val idx = emit_node(node_at(call, 2), scope);
    if (!is_int_type(idx.type))
        die_at(call->line, "aset!: index must be integer");
    const char *idx64 = idx.val;
    if (idx.type->kind != TY_I64) {
        const char *t = new_tmp();
        body_emit("  %s = sext %s %s to i64\n",
                  t, type_to_ir(idx.type), idx.val);
        idx64 = t;
    }
    Type *elem = p.type->elem;
    Val v = emit_node(node_at(call, 3), scope);
    if (v.type->kind != elem->kind)
        die_at(call->line, "aset!: value type mismatch");
    const char *gep = new_tmp();
    body_emit("  %s = getelementptr inbounds %s, ptr %s, i64 %s\n",
              gep, type_to_ir(elem), p.val, idx64);
    body_emit("  store %s %s, ptr %s, align %d\n",
              type_to_ir(elem), v.val, gep, type_align(elem));
    Val r = { ty_void, NULL };
    return r;
}

// (char "x") — returns i8 value of a single character
static Val emit_char(Node *call, Scope *scope) {
    (void)scope;
    if (node_len(call) != 2) die_at(call->line, "char expects 1 arg");
    Node *arg = node_at(call, 1);
    if (arg->kind != NODE_STR || strlen(arg->s) != 1)
        die_at(arg->line, "char: arg must be single-char string");
    Val r = { ty_i8, arena_printf("%d", (unsigned char)arg->s[0]) };
    return r;
}

static Val emit_addr_of(Node *call, Scope *scope) {
    if (node_len(call) != 2) die_at(call->line, "addr-of expects 1 arg");
    Node *target = node_at(call, 1);
    if (target->kind != NODE_SYM)
        die_at(target->line, "addr-of: target must be symbol");
    Sym *sym = scope_lookup(scope, target->s);
    if (!sym) die_at(target->line, "addr-of: undefined '%s'", target->s);
    if (sym->type->kind == TY_FN)
        die_at(target->line, "addr-of: cannot take address of function '%s'", target->s);
    // For locals, sym->ir_name is the alloca slot (%x.addr).
    // For globals, sym->ir_name is @x, which in LLVM IR IS the address.
    Type *pt = make_type(TY_PTR);
    pt->elem = sym->type;
    Val r = { pt, sym->ir_name };
    return r;
}

// (funcall-void fn) — call fn() as void() via pointer
static Val emit_funcall_void(Node *call, Scope *scope) {
    if (node_len(call) != 2) die_at(call->line, "funcall-void expects 1 arg");
    Val fn = emit_node(node_at(call, 1), scope);
    if (fn.type->kind != TY_PTR) die_at(call->line, "funcall-void: arg must be ptr");
    body_emit("  call void %s()\n", fn.val);
    Val r = { ty_void, NULL };
    return r;
}

// (funcall-ptr-1 fn arg) — call fn(arg) as ptr(ptr) via pointer, return ptr
static Val emit_funcall_ptr_1(Node *call, Scope *scope) {
    if (node_len(call) != 3) die_at(call->line, "funcall-ptr-1 expects 2 args");
    Val fn  = emit_node(node_at(call, 1), scope);
    Val arg = emit_node(node_at(call, 2), scope);
    if (fn.type->kind != TY_PTR)  die_at(call->line, "funcall-ptr-1: fn must be ptr");
    if (arg.type->kind != TY_PTR) die_at(call->line, "funcall-ptr-1: arg must be ptr");
    const char *tmp = new_tmp();
    body_emit("  %s = call ptr %s(ptr %s)\n", tmp, fn.val, arg.val);
    Val r = { ty_ptr, tmp };
    return r;
}

static Val emit_deref(Node *call, Scope *scope) {
    if (node_len(call) != 2) die_at(call->line, "deref expects 1 arg");
    Val p = emit_node(node_at(call, 1), scope);
    if (p.type->kind != TY_PTR || !p.type->elem)
        die_at(call->line, "deref: operand must be typed pointer");
    Type *elem = p.type->elem;
    const char *tmp = new_tmp();
    body_emit("  %s = load %s, ptr %s, align %d\n",
              tmp, type_to_ir(elem), p.val, type_align(elem));
    Val r = { elem, tmp };
    return r;
}

static Val emit_ptr_set(Node *call, Scope *scope) {
    if (node_len(call) != 3) die_at(call->line, "ptr-set! expects 2 args");
    Val p = emit_node(node_at(call, 1), scope);
    if (p.type->kind != TY_PTR || !p.type->elem)
        die_at(call->line, "ptr-set!: operand must be typed pointer");
    Type *elem = p.type->elem;
    Val v = emit_node(node_at(call, 2), scope);
    if (v.type->kind != elem->kind)
        die_at(call->line, "ptr-set!: value type mismatch");
    body_emit("  store %s %s, ptr %s, align %d\n",
              type_to_ir(elem), v.val, p.val, type_align(elem));
    Val r = { ty_void, NULL };
    return r;
}

static Val emit_ptr_add(Node *call, Scope *scope) {
    if (node_len(call) != 3) die_at(call->line, "ptr+ expects 2 args");
    Val p = emit_node(node_at(call, 1), scope);
    if (p.type->kind != TY_PTR || !p.type->elem)
        die_at(call->line, "ptr+: operand must be typed pointer");
    Val n = emit_node(node_at(call, 2), scope);
    if (!is_int_type(n.type))
        die_at(call->line, "ptr+: offset must be integer");
    const char *idx = n.val;
    if (n.type->kind != TY_I64) {
        const char *t = new_tmp();
        body_emit("  %s = sext %s %s to i64\n",
                  t, type_to_ir(n.type), n.val);
        idx = t;
    }
    Type *elem = p.type->elem;
    const char *tmp = new_tmp();
    body_emit("  %s = getelementptr inbounds %s, ptr %s, i64 %s\n",
              tmp, type_to_ir(elem), p.val, idx);
    Val r = { p.type, tmp };
    return r;
}

static Val emit_not(Node *call, Scope *scope) {
    if (node_len(call) != 2) die_at(call->line, "not expects 1 arg");
    Val a = emit_node(node_at(call, 1), scope);
    if (a.type->kind != TY_I1)
        die_at(call->line, "not expects i1 operand");
    const char *tmp = new_tmp();
    body_emit("  %s = xor i1 %s, 1\n", tmp, a.val);
    Val v = { ty_i1, tmp };
    return v;
}

// Short-circuit `and` / `or`. Result lives in a per-site i1 alloca so we
// don't need phi nodes (matches the rest of the codegen's alloca style).
static Val emit_short_circuit(Node *call, Scope *scope, bool is_and) {
    if (node_len(call) != 3)
        die_at(call->line, "%s expects 2 args", is_and ? "and" : "or");
    int id = new_label_id();
    const char *rhs_lbl = arena_printf("%s.rhs%d", is_and ? "and" : "or", id);
    const char *end_lbl = arena_printf("%s.end%d", is_and ? "and" : "or", id);
    const char *slot    = arena_printf("%%%s.val%d", is_and ? "and" : "or", id);

    entry_emit("  %s = alloca i1, align 1\n", slot);

    Val lhs = emit_node(node_at(call, 1), scope);
    if (lhs.type->kind != TY_I1)
        die_at(node_at(call, 1)->line,
               "%s expects i1 operands", is_and ? "and" : "or");
    body_emit("  store i1 %s, ptr %s, align 1\n", lhs.val, slot);
    if (is_and) {
        body_emit("  br i1 %s, label %%%s, label %%%s\n",
                  lhs.val, rhs_lbl, end_lbl);
    } else {
        body_emit("  br i1 %s, label %%%s, label %%%s\n",
                  lhs.val, end_lbl, rhs_lbl);
    }

    body_emit("%s:\n", rhs_lbl);
    g_block_term = false;
    Val rhs = emit_node(node_at(call, 2), scope);
    if (rhs.type->kind != TY_I1)
        die_at(node_at(call, 2)->line,
               "%s expects i1 operands", is_and ? "and" : "or");
    body_emit("  store i1 %s, ptr %s, align 1\n", rhs.val, slot);
    body_emit("  br label %%%s\n", end_lbl);

    body_emit("%s:\n", end_lbl);
    g_block_term = false;
    const char *tmp = new_tmp();
    body_emit("  %s = load i1, ptr %s, align 1\n", tmp, slot);
    Val v = { ty_i1, tmp };
    return v;
}

// Function call (handles variadic)
static Val emit_call(Node *call, Scope *scope, Sym *sym) {
    int nargs = node_len(call) - 1;
    Val *args = arena_alloc((size_t)nargs * sizeof(Val));
    for (int i = 0; i < nargs; i++) {
        args[i] = emit_node(node_at(call, i + 1), scope);
    }
    // Build comma-separated argument list
    char arglist[2048] = "";
    size_t apos = 0;
    for (int i = 0; i < nargs; i++) {
        int w = snprintf(arglist + apos, sizeof(arglist) - apos, "%s%s %s",
                         i ? ", " : "", type_to_ir(args[i].type), args[i].val);
        if (w < 0 || (size_t)w >= sizeof(arglist) - apos)
            die_at(call->line, "argument list too long");
        apos += (size_t)w;
    }

    Type *ft = sym->type;
    if (ft->kind != TY_FN) die_at(call->line, "not a function: %s", sym->name);

    Val result = { ty_void, NULL };

    if (ft->variadic) {
        // Variadic calls require the functional type at the call site:
        //   call i32 (ptr, ...) @printf(...)
        char sig[512];
        size_t sp = 0;
        sp += (size_t)snprintf(sig + sp, sizeof(sig) - sp, "%s (", type_to_ir(ft->ret));
        for (int i = 0; i < ft->num_params; i++) {
            sp += (size_t)snprintf(sig + sp, sizeof(sig) - sp, "%s%s",
                                   i ? ", " : "", type_to_ir(ft->params[i]));
        }
        snprintf(sig + sp, sizeof(sig) - sp, "%s...)", ft->num_params ? ", " : "");
        if (ft->ret->kind == TY_VOID) {
            body_emit("  call %s %s(%s)\n", sig, sym->ir_name, arglist);
        } else {
            const char *tmp = new_tmp();
            body_emit("  %s = call %s %s(%s)\n", tmp, sig, sym->ir_name, arglist);
            result.type = ft->ret;
            result.val = tmp;
        }
    } else {
        if (ft->ret->kind == TY_VOID) {
            body_emit("  call %s %s(%s)\n", type_to_ir(ft->ret), sym->ir_name, arglist);
        } else {
            const char *tmp = new_tmp();
            body_emit("  %s = call %s %s(%s)\n",
                      tmp, type_to_ir(ft->ret), sym->ir_name, arglist);
            result.type = ft->ret;
            result.val = tmp;
        }
    }
    return result;
}

// ------------------------------------------------------------
// Special forms
// ------------------------------------------------------------

static Val emit_return(Node *call, Scope *scope) {
    if (node_len(call) == 1) {
        body_emit("  ret void\n");
        g_block_term = true;
        Val r = { ty_void, NULL };
        return r;
    }
    if (node_len(call) != 2) die_at(call->line, "return expects 0 or 1 args");
    Val v = emit_node(node_at(call, 1), scope);
    body_emit("  ret %s %s\n", type_to_ir(v.type), v.val);
    g_block_term = true;
    Val r = { ty_void, NULL };
    return r;
}

// (do expr1 expr2 ...) — evaluate in order, return last
static Val emit_do(Node *call, Scope *scope) {
    Val last = { ty_void, NULL };
    for (int i = 1; i < node_len(call); i++) {
        last = emit_node(node_at(call, i), scope);
    }
    return last;
}

static Val emit_let(Node *call, Scope *scope) {
    // (let (name:type val ...) body...)
    if (node_len(call) < 2 || node_at(call, 1)->kind != NODE_CELL)
        die_at(call->line, "let: bad form");
    Node *binds = node_at(call, 1);
    if (node_len(binds) % 2 != 0)
        die_at(binds->line, "let: binding list must be even");

    Scope *inner = scope_new(scope);
    for (int i = 0; i < node_len(binds); i += 2) {
        Node *bname = node_at(binds, i);
        Node *bval  = node_at(binds, i + 1);
        if (bname->kind != NODE_SYM)
            die_at(bname->line, "let: binding name must be symbol");
        char *name, *type_name;
        split_typed(bname->s, &name, &type_name);
        if (!type_name)
            die_at(bname->line, "let: missing :type on '%s'", name);
        Type *ty = parse_type_name(type_name, bname->line);

        const char *slot = arena_printf("%%%s.addr.%d", name, g_tmp++);
        int align = type_align(ty);
        entry_emit("  %s = alloca %s, align %d\n", slot, type_to_ir(ty), align);

        Val v = emit_node(bval, inner);
        if (v.type->kind != ty->kind)
            die_at(bval->line, "let: init type mismatch for '%s'", name);
        body_emit("  store %s %s, ptr %s, align %d\n",
                  type_to_ir(ty), v.val, slot, align);

        scope_define(inner, name, ty, slot, true);
    }
    Val last = { ty_void, NULL };
    for (int i = 2; i < node_len(call); i++) {
        last = emit_node(node_at(call, i), inner);
    }
    return last;
}

static Val emit_cond(Node *call, Scope *scope) {
    int nargs = node_len(call) - 1;
    if (nargs < 2 || nargs % 2 != 0)
        die_at(call->line, "cond: expects pairs of (test body)");
    int npairs = nargs / 2;
    int id = new_label_id();
    const char *end_lbl = arena_printf("cond.end%d", id);

    for (int i = 0; i < npairs; i++) {
        const char *then_lbl = arena_printf("cond.then%d.%d", id, i);
        const char *next_lbl = (i < npairs - 1)
            ? arena_printf("cond.test%d.%d", id, i + 1) : end_lbl;

        Val test = emit_node(node_at(call, 1 + i * 2), scope);
        if (test.type->kind != TY_I1)
            die_at(node_at(call, 1 + i * 2)->line, "cond: test must be i1");
        body_emit("  br i1 %s, label %%%s, label %%%s\n",
                  test.val, then_lbl, next_lbl);

        body_emit("%s:\n", then_lbl);
        g_block_term = false;
        emit_node(node_at(call, 2 + i * 2), scope);
        if (!g_block_term)
            body_emit("  br label %%%s\n", end_lbl);

        if (i < npairs - 1) {
            body_emit("%s:\n", next_lbl);
            g_block_term = false;
        }
    }

    body_emit("%s:\n", end_lbl);
    g_block_term = false;
    Val r = { ty_void, NULL };
    return r;
}

static Val emit_while(Node *call, Scope *scope) {
    if (node_len(call) < 2) die_at(call->line, "while: missing condition");
    int id = new_label_id();
    const char *cond_lbl = arena_printf("while.cond%d", id);
    const char *body_lbl = arena_printf("while.body%d", id);
    const char *end_lbl  = arena_printf("while.end%d",  id);

    body_emit("  br label %%%s\n", cond_lbl);
    body_emit("%s:\n", cond_lbl);
    g_block_term = false;
    Val cond = emit_node(node_at(call, 1), scope);
    if (cond.type->kind != TY_I1)
        die_at(node_at(call, 1)->line, "while condition must be i1");
    body_emit("  br i1 %s, label %%%s, label %%%s\n",
              cond.val, body_lbl, end_lbl);

    body_emit("%s:\n", body_lbl);
    g_block_term = false;
    for (int i = 2; i < node_len(call); i++) {
        emit_node(node_at(call, i), scope);
    }
    if (!g_block_term) body_emit("  br label %%%s\n", cond_lbl);

    body_emit("%s:\n", end_lbl);
    g_block_term = false;
    Val r = { ty_void, NULL };
    return r;
}

static Val emit_set(Node *call, Scope *scope) {
    if (node_len(call) != 3) die_at(call->line, "set! expects 2 args");
    Node *target = node_at(call, 1);
    if (target->kind != NODE_SYM)
        die_at(target->line, "set!: target must be symbol");
    Sym *sym = scope_lookup(scope, target->s);
    if (!sym || !sym->is_local)
        die_at(target->line, "set!: undefined local '%s'", target->s);
    Val v = emit_node(node_at(call, 2), scope);
    if (v.type->kind != sym->type->kind)
        die_at(call->line, "set!: type mismatch for '%s'", target->s);
    body_emit("  store %s %s, ptr %s, align %d\n",
              type_to_ir(sym->type), v.val, sym->ir_name, type_align(sym->type));
    Val r = { ty_void, NULL };
    return r;
}

static Val emit_inc(Node *call, Scope *scope) {
    if (node_len(call) != 2) die_at(call->line, "inc! expects 1 arg");
    Node *target = node_at(call, 1);
    if (target->kind != NODE_SYM)
        die_at(target->line, "inc!: target must be symbol");
    Sym *sym = scope_lookup(scope, target->s);
    if (!sym || !sym->is_local)
        die_at(target->line, "inc!: undefined local '%s'", target->s);
    if (!is_int_type(sym->type) || sym->type->kind == TY_I1)
        die_at(call->line, "inc!: must be integer");
    const char *ir = type_to_ir(sym->type);
    int align = type_align(sym->type);
    const char *t1 = new_tmp();
    body_emit("  %s = load %s, ptr %s, align %d\n", t1, ir, sym->ir_name, align);
    const char *t2 = new_tmp();
    body_emit("  %s = add nsw %s %s, 1\n", t2, ir, t1);
    body_emit("  store %s %s, ptr %s, align %d\n", ir, t2, sym->ir_name, align);
    Val r = { ty_void, NULL };
    return r;
}

static Val emit_list(Node *n, Scope *scope) {
    if (node_len(n) == 0) die_at(n->line, "empty list");
    Node *head = node_at(n, 0);
    if (head->kind != NODE_SYM) die_at(head->line, "list head must be symbol");
    const char *h = head->s;

    // Check macro table before special forms.
    for (int i = 0; i < g_num_macros; i++) {
        if (strcmp(g_macros[i].name, h) == 0)
            return emit_macro_call(n, scope, i);
    }

    if (strcmp(h, "gensym") == 0) {
        if (node_len(n) != 1) die_at(n->line, "gensym: expects no args");
        const char *tmp = new_tmp();
        body_emit("  %s = call ptr @nucleus_gensym()\n", tmp);
        Val r = { ty_ptr, tmp };
        return r;
    }
    if (strcmp(h, "funcall-ptr-1") == 0) return emit_funcall_ptr_1(n, scope);

    if (strcmp(h, "return") == 0) return emit_return(n, scope);
    if (strcmp(h, "do")     == 0) return emit_do(n, scope);
    if (strcmp(h, "let")    == 0) return emit_let(n, scope);
    if (strcmp(h, "cond")   == 0) return emit_cond(n, scope);
    if (strcmp(h, "quote")  == 0) return emit_quote(n);
    if (strcmp(h, "quasiquote") == 0) return emit_quasiquote(n, scope);
    if (strcmp(h, "while")  == 0) return emit_while(n, scope);
    if (strcmp(h, "set!")   == 0) return emit_set(n, scope);
    if (strcmp(h, "inc!")   == 0) return emit_inc(n, scope);
    if (strcmp(h, "not")     == 0) return emit_not(n, scope);
    if (strcmp(h, "and")     == 0) return emit_short_circuit(n, scope, true);
    if (strcmp(h, "or")      == 0) return emit_short_circuit(n, scope, false);
    if (strcmp(h, "cast")    == 0) return emit_cast(n, scope);
    if (strcmp(h, "addr-of") == 0) return emit_addr_of(n, scope);
    if (strcmp(h, "funcall-void") == 0) return emit_funcall_void(n, scope);
    if (strcmp(h, "deref")   == 0) return emit_deref(n, scope);
    if (strcmp(h, "ptr-set!") == 0) return emit_ptr_set(n, scope);
    if (strcmp(h, "ptr+")    == 0) return emit_ptr_add(n, scope);
    if (strcmp(h, ".")       == 0) return emit_field_get(n, scope);
    if (strcmp(h, ".set!")   == 0) return emit_field_set(n, scope);
    if (strcmp(h, "sizeof")  == 0) return emit_sizeof(n, scope);
    if (strcmp(h, "alloca")  == 0) return emit_alloca_form(n, scope);
    if (strcmp(h, "char")    == 0) return emit_char(n, scope);
    if (strcmp(h, "aref")    == 0) return emit_aref(n, scope);
    if (strcmp(h, "aset!")   == 0) return emit_aset(n, scope);

    const BinOp *op = lookup_binop(h);
    if (op) return emit_binop(n, scope, op);

    Sym *sym = scope_lookup(scope, h);
    if (!sym) die_at(head->line, "unknown: %s", h);
    return emit_call(n, scope, sym);
}

static Val emit_node(Node *n, Scope *scope) {
    switch (n->kind) {
        case NODE_INT:  return emit_int(n);
        case NODE_STR:  return emit_string(n);
        case NODE_SYM:  return emit_symbol_ref(n, scope);
        case NODE_CELL: return emit_list(n, scope);
    }
    Val r = { ty_void, NULL };
    return r;
}

// ------------------------------------------------------------
// Top-level forms
// ------------------------------------------------------------

static void emit_defvar(Node *call) {
    // (defvar name:type) or (defvar name:type init)
    if (node_len(call) < 2 || node_len(call) > 3)
        die_at(call->line, "defvar: expects name and optional init");
    Node *name_node = node_at(call, 1);
    if (name_node->kind != NODE_SYM)
        die_at(name_node->line, "defvar: name must be symbol");
    char *name, *type_name;
    split_typed(name_node->s, &name, &type_name);
    if (!type_name)
        die_at(name_node->line, "defvar: missing :type on '%s'", name);
    Type *ty = parse_type_name(type_name, name_node->line);
    const char *ir_name = arena_printf("@%s", name);
    int align = type_align(ty);
    if (node_len(call) == 3) {
        Node *init = node_at(call, 2);
        if (init->kind != NODE_INT)
            die_at(init->line, "defvar: init must be integer literal");
        fprintf(g_out, "%s = global %s %ld, align %d\n\n",
                ir_name, type_to_ir(ty), init->i, align);
    } else {
        const char *zero = (ty->kind == TY_PTR) ? "null" : "0";
        fprintf(g_out, "%s = global %s %s, align %d\n\n",
                ir_name, type_to_ir(ty), zero, align);
    }
    // is_local=true so load/store via symbol ref and set! work on the @global addr
    scope_define(g_globals, name, ty, ir_name, true);
}

static void emit_defconst(Node *call) {
    // (defconst NAME integer-literal)
    if (node_len(call) != 3) die_at(call->line, "defconst: expects name and value");
    Node *name = node_at(call, 1);
    Node *val  = node_at(call, 2);
    if (name->kind != NODE_SYM)
        die_at(name->line, "defconst: name must be symbol");
    if (val->kind != NODE_INT)
        die_at(val->line, "defconst: value must be integer literal");
    Sym *sym = scope_define(g_globals, name->s, ty_i32, NULL, false);
    sym->is_const = true;
    sym->const_val = arena_printf("%ld", val->i);
}

static void emit_defenum(Node *call) {
    // (defenum EnumName VAL0 VAL1 ...) — defines VALi = i
    if (node_len(call) < 2) die_at(call->line, "defenum: missing name");
    for (int i = 2; i < node_len(call); i++) {
        Node *name = node_at(call, i);
        if (name->kind != NODE_SYM)
            die_at(name->line, "defenum: value must be symbol");
        Sym *sym = scope_define(g_globals, name->s, ty_i32, NULL, false);
        sym->is_const = true;
        sym->const_val = arena_printf("%d", i - 2);
    }
}

static void emit_defstruct(Node *call) {
    // (defstruct Name field1:type1 field2:type2 ...)
    if (node_len(call) < 2) die_at(call->line, "defstruct: missing name");
    Node *name_node = node_at(call, 1);
    if (name_node->kind != NODE_SYM)
        die_at(name_node->line, "defstruct: name must be symbol");
    StructDef *sd = register_struct(name_node->s);
    int nfields = node_len(call) - 2;
    sd->field_names = arena_alloc((size_t)nfields * sizeof(char *));
    sd->field_types = arena_alloc((size_t)nfields * sizeof(Type *));
    sd->num_fields = nfields;
    for (int i = 0; i < nfields; i++) {
        Node *field = node_at(call, i + 2);
        if (field->kind != NODE_SYM)
            die_at(field->line, "defstruct: field must be typed symbol");
        char *fname, *ftype_name;
        split_typed(field->s, &fname, &ftype_name);
        if (!ftype_name)
            die_at(field->line, "defstruct: field '%s' missing :type", fname);
        sd->field_names[i] = fname;
        sd->field_types[i] = parse_type_name(ftype_name, field->line);
    }
    fprintf(g_out, "%%%s = type { ", name_node->s);
    for (int i = 0; i < nfields; i++) {
        if (i) fprintf(g_out, ", ");
        fprintf(g_out, "%s", type_to_ir(sd->field_types[i]));
    }
    fprintf(g_out, " }\n\n");
}

typedef struct {
    const char *module;
    const char *name;
    TypeKind    ret;
    TypeKind    params[6];
    int         num_params;
    bool        variadic;
} LibcDecl;

static const LibcDecl g_libc[] = {
    // stdio
    {"stdio", "printf",   TY_I32,  {TY_PTR},                         1, true },
    {"stdio", "fprintf",  TY_I32,  {TY_PTR, TY_PTR},                 2, true },
    {"stdio", "snprintf", TY_I32,  {TY_PTR, TY_I64, TY_PTR},         3, true },
    {"stdio", "fputc",    TY_I32,  {TY_I32, TY_PTR},                 2, false},
    {"stdio", "fputs",    TY_I32,  {TY_PTR, TY_PTR},                 2, false},
    {"stdio", "fopen",    TY_PTR,  {TY_PTR, TY_PTR},                 2, false},
    {"stdio", "fclose",   TY_I32,  {TY_PTR},                         1, false},
    {"stdio", "fread",    TY_I64,  {TY_PTR, TY_I64, TY_I64, TY_PTR}, 4, false},
    {"stdio", "fwrite",   TY_I64,  {TY_PTR, TY_I64, TY_I64, TY_PTR}, 4, false},
    {"stdio", "fseek",    TY_I32,  {TY_PTR, TY_I64, TY_I32},         3, false},
    {"stdio", "ftell",    TY_I64,  {TY_PTR},                         1, false},
    {"stdio", "rewind",   TY_VOID, {TY_PTR},                         1, false},
    {"stdio", "perror",   TY_VOID, {TY_PTR},                         1, false},
    {"stdio", "open_memstream", TY_PTR, {TY_PTR, TY_PTR},            2, false},
    {"stdio", "fflush",  TY_I32, {TY_PTR},                          1, false},
    // stdlib
    {"stdlib", "malloc",  TY_PTR,  {TY_I64},                         1, false},
    {"stdlib", "realloc", TY_PTR,  {TY_PTR, TY_I64},                 2, false},
    {"stdlib", "free",    TY_VOID, {TY_PTR},                         1, false},
    {"stdlib", "exit",    TY_VOID, {TY_I32},                         1, false},
    {"stdlib", "strtol",  TY_I64,  {TY_PTR, TY_PTR, TY_I32},         3, false},
    // string
    {"string", "memcpy",  TY_PTR, {TY_PTR, TY_PTR, TY_I64},         3, false},
    {"string", "memset",  TY_PTR, {TY_PTR, TY_I32, TY_I64},         3, false},
    {"string", "memcmp",  TY_I32, {TY_PTR, TY_PTR, TY_I64},         3, false},
    {"string", "strlen",  TY_I64, {TY_PTR},                          1, false},
    {"string", "strcmp",   TY_I32, {TY_PTR, TY_PTR},                 2, false},
    {"string", "strncmp", TY_I32,  {TY_PTR, TY_PTR, TY_I64},         3, false},
    {"string", "strchr",  TY_PTR,  {TY_PTR, TY_I32},                 2, false},
    {"string", "strndup", TY_PTR,  {TY_PTR, TY_I64},                 2, false},
    // ctype
    {"ctype", "isspace", TY_I32, {TY_I32}, 1, false},
    {"ctype", "isdigit", TY_I32, {TY_I32}, 1, false},
    // unistd — POSIX fd helpers needed for CT stdout redirect
    {"unistd", "dup",   TY_I32,  {TY_I32},         1, false},
    {"unistd", "dup2",  TY_I32,  {TY_I32, TY_I32}, 2, false},
    {"unistd", "close", TY_I32,  {TY_I32},         1, false},
    // llvm — LLVM C API for compile-time JIT (used by nucleusc.nuc self-hosted compiler)
    // X86 target initialization (concrete functions behind LLVMInitializeNativeTarget macro)
    {"llvm", "LLVMInitializeX86TargetInfo", TY_VOID, {0}, 0, false},
    {"llvm", "LLVMInitializeX86Target",     TY_VOID, {0}, 0, false},
    {"llvm", "LLVMInitializeX86TargetMC",   TY_VOID, {0}, 0, false},
    {"llvm", "LLVMInitializeX86AsmPrinter", TY_VOID, {0}, 0, false},
    // ORC LLJIT
    {"llvm", "LLVMOrcCreateLLJIT",          TY_PTR,  {TY_PTR, TY_PTR}, 2, false},
    {"llvm", "LLVMOrcLLJITGetMainJITDylib", TY_PTR,  {TY_PTR}, 1, false},
    {"llvm", "LLVMOrcLLJITGetGlobalPrefix", TY_I8,   {TY_PTR}, 1, false},
    {"llvm", "LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess",
                                            TY_PTR,  {TY_PTR, TY_I8, TY_PTR, TY_PTR}, 4, false},
    {"llvm", "LLVMOrcJITDylibAddGenerator", TY_VOID, {TY_PTR, TY_PTR}, 2, false},
    // Thread-safe context / module
    {"llvm", "LLVMContextCreate",                    TY_PTR, {0}, 0, false},
    {"llvm", "LLVMOrcCreateNewThreadSafeContext",    TY_PTR, {0}, 0, false},
    {"llvm", "LLVMOrcDisposeThreadSafeContext",      TY_VOID, {TY_PTR}, 1, false},
    {"llvm", "LLVMOrcCreateNewThreadSafeModule",     TY_PTR, {TY_PTR, TY_PTR}, 2, false},
    // Memory buffer / IR parsing
    {"llvm", "LLVMCreateMemoryBufferWithMemoryRangeCopy",
                                            TY_PTR, {TY_PTR, TY_I64, TY_PTR}, 3, false},
    {"llvm", "LLVMParseIRInContext",        TY_I32, {TY_PTR, TY_PTR, TY_PTR, TY_PTR}, 4, false},
    // Add module and lookup
    {"llvm", "LLVMOrcLLJITAddLLVMIRModule",TY_PTR, {TY_PTR, TY_PTR, TY_PTR}, 3, false},
    {"llvm", "LLVMOrcLLJITLookup",         TY_PTR, {TY_PTR, TY_PTR, TY_PTR}, 3, false},
    // Error handling
    {"llvm", "LLVMGetErrorMessage",         TY_PTR, {TY_PTR}, 1, false},
    {"llvm", "LLVMDisposeErrorMessage",     TY_VOID, {TY_PTR}, 1, false},
    {"llvm", "LLVMConsumeError",            TY_VOID, {TY_PTR}, 1, false},
};

static Type *kind_to_type(TypeKind k) {
    switch (k) {
        case TY_VOID: return ty_void;
        case TY_I8:   return ty_i8;
        case TY_I32:  return ty_i32;
        case TY_I64:  return ty_i64;
        case TY_PTR:  return ty_ptr;
        default:      return ty_void;
    }
}

static void emit_extern(Node *call) {
    // (extern name:type) — declare an external global (e.g. stderr)
    if (node_len(call) != 2 || node_at(call, 1)->kind != NODE_SYM)
        die_at(call->line, "extern: expects name:type");
    char *name, *type_name;
    split_typed(node_at(call, 1)->s, &name, &type_name);
    if (!type_name)
        die_at(node_at(call, 1)->line, "extern: missing :type on '%s'", name);
    Type *ty = parse_type_name(type_name, node_at(call, 1)->line);
    const char *ir_name = arena_printf("@%s", name);
    fprintf(g_out, "%s = external global %s\n\n", ir_name, type_to_ir(ty));
    scope_define(g_globals, name, ty, ir_name, true);
}

static void emit_include(Node *call) {
    if (node_len(call) != 2 || node_at(call, 1)->kind != NODE_SYM)
        die_at(call->line, "include: expects one symbol");
    const char *mod = node_at(call, 1)->s;
    bool found = false;
    for (size_t i = 0; i < sizeof(g_libc) / sizeof(g_libc[0]); i++) {
        const LibcDecl *d = &g_libc[i];
        if (strcmp(d->module, mod) != 0) continue;
        found = true;
        Type *ft = make_type(TY_FN);
        ft->ret = kind_to_type(d->ret);
        ft->num_params = d->num_params;
        ft->params = arena_alloc((size_t)d->num_params * sizeof(Type *));
        for (int j = 0; j < d->num_params; j++)
            ft->params[j] = kind_to_type(d->params[j]);
        ft->variadic = d->variadic;
        scope_define(g_globals, d->name, ft,
                     arena_printf("@%s", d->name), false);
        fprintf(g_out, "declare %s @%s(", type_to_ir(ft->ret), d->name);
        for (int j = 0; j < d->num_params; j++) {
            if (j) fprintf(g_out, ", ");
            fprintf(g_out, "%s", type_to_ir(ft->params[j]));
        }
        if (d->variadic)
            fprintf(g_out, "%s...", d->num_params ? ", " : "");
        fprintf(g_out, ")\n");
    }
    if (found) fprintf(g_out, "\n");
    if (!found) die_at(call->line, "unknown include: %s", mod);
}

static void emit_defn(Node *call) {
    // (defn name:type (params...) body...)
    if (node_len(call) < 4) die_at(call->line, "defn: bad form");
    Node *name_node = node_at(call, 1);
    Node *params_node = node_at(call, 2);
    if (name_node->kind != NODE_SYM)
        die_at(name_node->line, "defn: name must be symbol");
    if (!node_is_list(params_node))
        die_at(name_node->line, "defn: params must be list");

    char *fname, *ret_name;
    split_typed(name_node->s, &fname, &ret_name);
    if (!ret_name) die_at(name_node->line, "defn: missing :type on '%s'", fname);
    Type *ret = parse_type_name(ret_name, name_node->line);

    int nparams = node_len(params_node);
    Type **param_types = NULL;
    char **param_names = NULL;
    if (nparams > 0) {
        param_types = arena_alloc((size_t)nparams * sizeof(Type *));
        param_names = arena_alloc((size_t)nparams * sizeof(char *));
    }
    for (int i = 0; i < nparams; i++) {
        Node *p = node_at(params_node, i);
        if (p->kind != NODE_SYM)
            die_at(p->line, "defn: param must be symbol");
        char *pname, *ptype_name;
        split_typed(p->s, &pname, &ptype_name);
        if (!ptype_name)
            die_at(p->line, "defn: missing :type on param '%s'", pname);
        param_types[i] = parse_type_name(ptype_name, p->line);
        param_names[i] = pname;
    }

    // Register the function in globals before body emission so recursive
    // calls can resolve the name.
    Type *ft = make_type(TY_FN);
    ft->ret = ret;
    ft->num_params = nparams;
    ft->params = param_types;
    ft->variadic = false;
    scope_define(g_globals, fname, ft, arena_printf("@%s", fname), false);

    reset_function_state();
    Scope *fn_scope = scope_new(g_globals);

    // Entry allocas + store of incoming argument for each parameter.
    for (int i = 0; i < nparams; i++) {
        const char *slot = arena_printf("%%%s.addr", param_names[i]);
        const char *arg  = arena_printf("%%%s.arg",  param_names[i]);
        int palign = type_align(param_types[i]);
        entry_emit("  %s = alloca %s, align %d\n",
                   slot, type_to_ir(param_types[i]), palign);
        entry_emit("  store %s %s, ptr %s, align %d\n",
                   type_to_ir(param_types[i]), arg, slot, palign);
        scope_define(fn_scope, param_names[i], param_types[i], slot, true);
    }

    for (int i = 3; i < node_len(call); i++) {
        emit_node(node_at(call, i), fn_scope);
    }
    if (!g_block_term) {
        if (ret->kind == TY_VOID) body_emit("  ret void\n");
        else {
            const char *zero = (ret->kind == TY_PTR) ? "null" : "0";
            body_emit("  ret %s %s\n", type_to_ir(ret), zero);
        }
    }

    fprintf(g_out, "define %s @%s(", type_to_ir(ret), fname);
    for (int i = 0; i < nparams; i++) {
        fprintf(g_out, "%s%s %%%s.arg",
                i ? ", " : "",
                type_to_ir(param_types[i]),
                param_names[i]);
    }
    fprintf(g_out, ") {\n");
    fprintf(g_out, "entry:\n");
    if (g_entry_buf && g_entry_buf[0]) fputs(g_entry_buf, g_out);
    if (g_body_buf  && g_body_buf[0])  fputs(g_body_buf,  g_out);
    fprintf(g_out, "}\n\n");
}

// ============================================================
// compile-time special form
// ============================================================

// Forward declarations for functions defined later in this file.
static void emit_string_table(FILE *out);
static void jit_add_module(const char *ir, int line);
static void jit_call_ct_main_sym(int line, const char *sym);
static void emit_defmacro(Node *form);

// Shared QQ helper IR (using private linkage to avoid conflicts between CT modules)
static const char *k_qq_helpers =
    "define private ptr @__cons(ptr %a, ptr %b) {\n"
    "  %c = call ptr @malloc(i64 40)\n"
    "  %p0 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %c, i32 0, i32 0\n"
    "  store i32 3, ptr %p0, align 8\n"
    "  %p1 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %c, i32 0, i32 1\n"
    "  store i32 0, ptr %p1, align 4\n"
    "  %p2 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %c, i32 0, i32 2\n"
    "  store i64 0, ptr %p2, align 8\n"
    "  %p3 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %c, i32 0, i32 3\n"
    "  store ptr null, ptr %p3, align 8\n"
    "  %p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %c, i32 0, i32 4\n"
    "  store ptr %a, ptr %p4, align 8\n"
    "  %p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %c, i32 0, i32 5\n"
    "  store ptr %b, ptr %p5, align 8\n"
    "  ret ptr %c\n"
    "}\n\n"
    "define private ptr @__append(ptr %a, ptr %b) {\n"
    "entry:\n"
    "  %z = icmp eq ptr %a, null\n"
    "  br i1 %z, label %nil, label %rec\n"
    "nil:\n"
    "  ret ptr %b\n"
    "rec:\n"
    "  %p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %a, i32 0, i32 4\n"
    "  %car = load ptr, ptr %p4, align 8\n"
    "  %p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %a, i32 0, i32 5\n"
    "  %cdr = load ptr, ptr %p5, align 8\n"
    "  %rest = call ptr @__append(ptr %cdr, ptr %b)\n"
    "  %c = call ptr @__cons(ptr %car, ptr %rest)\n"
    "  ret ptr %c\n"
    "}\n\n";

static void emit_compile_time(Node *form) {
    // (compile-time body-form...)
    int nforms = node_len(form);
    if (nforms < 2)
        die_at(form->line, "compile-time: expected at least one body form");

    // Snapshot current main streams so the CT module can use their content as preamble.
    fflush(g_type_stream);
    fflush(g_decl_stream);

    // Fresh streams for the compile-time module.
    char *ct_type_buf = NULL, *ct_decl_buf = NULL, *ct_def_buf = NULL;
    size_t ct_type_sz = 0, ct_decl_sz = 0, ct_def_sz = 0;
    FILE *ct_type = open_memstream(&ct_type_buf, &ct_type_sz);
    FILE *ct_decl = open_memstream(&ct_decl_buf, &ct_decl_sz);
    FILE *ct_def  = open_memstream(&ct_def_buf,  &ct_def_sz);

    // Redirect global state to CT streams.
    FILE *saved_g_out    = g_out;
    FILE *saved_decl_out = g_decl_out;
    bool  saved_qq_used  = g_qq_used;
    g_qq_used  = false;
    g_decl_out = ct_decl; // quote globals go into CT decl

    // Pre-scan: register defn signatures from CT body so mutual/forward calls work.
    for (int i = 1; i < nforms; i++) {
        Node *bf = node_at(form, i);
        if (!bf || bf->kind != NODE_CELL || node_len(bf) < 4) continue;
        Node *head = node_at(bf, 0);
        if (!head || head->kind != NODE_SYM || strcmp(head->s, "defn") != 0) continue;
        Node *name_node   = node_at(bf, 1);
        Node *params_node = node_at(bf, 2);
        if (!name_node || name_node->kind != NODE_SYM || !node_is_list(params_node)) continue;
        char *fname, *ret_name;
        split_typed(name_node->s, &fname, &ret_name);
        if (!ret_name) continue;
        Type *ret = parse_type_name(ret_name, name_node->line);
        int nparams = node_len(params_node);
        Type **ptypes = nparams ? arena_alloc((size_t)nparams * sizeof(Type *)) : NULL;
        for (int j = 0; j < nparams; j++) {
            Node *p = node_at(params_node, j);
            if (p->kind != NODE_SYM) continue;
            char *pn, *pt;
            split_typed(p->s, &pn, &pt);
            ptypes[j] = pt ? parse_type_name(pt, p->line) : ty_i32;
        }
        Type *ft = make_type(TY_FN);
        ft->ret = ret; ft->num_params = nparams; ft->params = ptypes;
        scope_define(g_globals, fname, ft, arena_printf("@%s", fname), false);
    }

    // Collect non-top-level expression forms for @__compile_time_main.
    Node *expr_forms[256];
    int   nexpr = 0;

    for (int i = 1; i < nforms; i++) {
        Node *bf = node_at(form, i);
        if (!bf) continue;
        bool is_toplevel = false;
        if (bf->kind == NODE_CELL && node_at(bf, 0) &&
            node_at(bf, 0)->kind == NODE_SYM) {
            const char *h = node_at(bf, 0)->s;
            if (strcmp(h, "defstruct") == 0) {
                is_toplevel = true;
                g_out = ct_type; emit_defstruct(bf);
            } else if (strcmp(h, "defconst") == 0) {
                is_toplevel = true; emit_defconst(bf);
            } else if (strcmp(h, "defenum") == 0) {
                is_toplevel = true; emit_defenum(bf);
            } else if (strcmp(h, "defvar") == 0) {
                is_toplevel = true;
                g_out = ct_decl; emit_defvar(bf);
            } else if (strcmp(h, "include") == 0) {
                is_toplevel = true;
                g_out = ct_decl; emit_include(bf);
            } else if (strcmp(h, "extern") == 0) {
                is_toplevel = true;
                g_out = ct_decl; emit_extern(bf);
            } else if (strcmp(h, "defn") == 0) {
                is_toplevel = true;
                g_out = ct_def; emit_defn(bf);
            }
        }
        if (!is_toplevel) {
            if (nexpr < 256) expr_forms[nexpr++] = bf;
        }
    }

    // Emit @__compile_time_main_N (unique per compile-time block) to call the collected expression forms.
    int ct_id = g_ct_id++;
    char ct_main_sym[64];
    snprintf(ct_main_sym, sizeof(ct_main_sym), "__compile_time_main_%d", ct_id);
    g_out = ct_def;
    reset_function_state();
    Scope *fn_scope = scope_new(g_globals);
    for (int i = 0; i < nexpr; i++)
        emit_node(expr_forms[i], fn_scope);
    if (!g_block_term) body_emit("  ret void\n");
    fprintf(ct_def, "define void @%s() {\n", ct_main_sym);
    fprintf(ct_def, "entry:\n");
    if (g_entry_buf && g_entry_buf[0]) fputs(g_entry_buf, ct_def);
    if (g_body_buf  && g_body_buf[0])  fputs(g_body_buf,  ct_def);
    fprintf(ct_def, "}\n\n");

    bool ct_qq = g_qq_used;

    // Restore global state.
    g_out      = saved_g_out;
    g_decl_out = saved_decl_out;
    g_qq_used  = saved_qq_used;

    // If CT body used quasiquote, add private helpers.
    if (ct_qq) {
        fprintf(ct_decl, "declare ptr @malloc(i64)\n");
        fputs(k_qq_helpers, ct_def);
    }

    fclose(ct_type);
    fclose(ct_decl);
    fclose(ct_def);

    // Assemble the full CT module IR.
    char  *ir_buf = NULL;
    size_t ir_sz  = 0;
    FILE  *irs    = open_memstream(&ir_buf, &ir_sz);
    fprintf(irs, "; ModuleID = '<compile-time>'\n");
    fprintf(irs, "target triple = \"x86_64-pc-linux-gnu\"\n\n");
    // Type definitions: main-so-far + any new ones from CT body
    if (g_type_buf && g_type_buf[0]) fputs(g_type_buf, irs);
    if (ct_type_buf && ct_type_buf[0]) fputs(ct_type_buf, irs);
    // String constants
    emit_string_table(irs);
    // External declarations: main-so-far + CT-specific ones
    if (g_decl_buf && g_decl_buf[0]) fputs(g_decl_buf, irs);
    if (ct_decl_buf && ct_decl_buf[0]) fputs(ct_decl_buf, irs);
    // Function definitions from CT body + @__compile_time_main
    if (ct_def_buf && ct_def_buf[0]) fputs(ct_def_buf, irs);
    fclose(irs);

    jit_add_module(ir_buf, form->line);
    jit_call_ct_main_sym(form->line, ct_main_sym);

    free(ct_type_buf);
    free(ct_decl_buf);
    free(ct_def_buf);
    free(ir_buf);
}

// ============================================================
// defmacro top-level form + macro expansion
// ============================================================

static void emit_defmacro(Node *form) {
    // (defmacro name (params...) body...)
    if (node_len(form) < 4)
        die_at(form->line, "defmacro: expects name, params, and body");
    Node *name_node = node_at(form, 1);
    if (name_node->kind != NODE_SYM)
        die_at(name_node->line, "defmacro: name must be symbol");
    const char *name = name_node->s;
    Node *params_node = node_at(form, 2);
    if (!node_is_list(params_node))
        die_at(name_node->line, "defmacro: params must be a list");
    int num_params = node_len(params_node);
    if (num_params > 8)
        die_at(name_node->line, "defmacro: maximum 8 parameters");

    // Collect param names.
    const char **pnames = num_params
        ? arena_alloc((size_t)num_params * sizeof(char *)) : NULL;
    for (int i = 0; i < num_params; i++) {
        Node *p = node_at(params_node, i);
        if (p->kind != NODE_SYM)
            die_at(p->line, "defmacro: param must be a symbol");
        pnames[i] = p->s;
    }

    // Register in macro table.
    if (g_num_macros >= MAX_MACROS)
        die_at(form->line, "defmacro: macro table full");
    const char *jit_name = arena_printf("__macro_%s", sanitize_for_ir(name));
    g_macros[g_num_macros].name       = name;
    g_macros[g_num_macros].jit_name   = jit_name;
    g_macros[g_num_macros].num_params = num_params;
    g_num_macros++;

    // Compile the macro body to a JIT module.
    fflush(g_type_stream);
    fflush(g_decl_stream);

    char  *ct_decl_buf = NULL, *ct_def_buf = NULL;
    size_t ct_decl_sz  = 0,     ct_def_sz  = 0;
    FILE  *ct_decl = open_memstream(&ct_decl_buf, &ct_decl_sz);
    FILE  *ct_def  = open_memstream(&ct_def_buf,  &ct_def_sz);

    FILE *saved_g_out    = g_out;
    FILE *saved_decl_out = g_decl_out;
    bool  saved_qq_used  = g_qq_used;
    g_qq_used  = false;
    g_decl_out = ct_decl;
    g_out      = ct_def;

    // Build the macro function.
    // Signature: ptr @__macro_name(ptr %__args.arg)
    // where %__args.arg is a Node*[] pointer.
    reset_function_state();
    Scope *fn_scope = scope_new(g_globals);

    // Alloca for the args pointer.
    entry_emit("  %%__args.addr = alloca ptr, align 8\n");
    entry_emit("  store ptr %%__args.arg, ptr %%__args.addr, align 8\n");

    // Load each named param from args[i].
    for (int i = 0; i < num_params; i++) {
        entry_emit("  %%%s.addr = alloca ptr, align 8\n", pnames[i]);
        entry_emit("  %%__argsptr.%d = load ptr, ptr %%__args.addr, align 8\n", i);
        entry_emit("  %%__argsgep.%d = getelementptr ptr, ptr %%__argsptr.%d, i32 %d\n",
                   i, i, i);
        entry_emit("  %%__argsval.%d = load ptr, ptr %%__argsgep.%d, align 8\n", i, i);
        entry_emit("  store ptr %%__argsval.%d, ptr %%%s.addr, align 8\n", i, pnames[i]);
        scope_define(fn_scope, pnames[i], ty_ptr, arena_printf("%%%s.addr", pnames[i]), true);
    }

    // Emit body; last expression is the return value.
    Val last = { ty_ptr, "null" };
    for (int i = 3; i < node_len(form); i++)
        last = emit_node(node_at(form, i), fn_scope);

    // Return the ptr result.
    const char *ret_val = "null";
    if (last.val && last.type && last.type->kind == TY_PTR)
        ret_val = last.val;
    body_emit("  ret ptr %s\n", ret_val);

    bool macro_qq = g_qq_used;
    g_out      = saved_g_out;
    g_decl_out = saved_decl_out;
    g_qq_used  = saved_qq_used;

    // Finalize the function definition.
    fprintf(ct_def, "define ptr @%s(ptr %%__args.arg) {\n", jit_name);
    fprintf(ct_def, "entry:\n");
    if (g_entry_buf && g_entry_buf[0]) fputs(g_entry_buf, ct_def);
    if (g_body_buf  && g_body_buf[0])  fputs(g_body_buf,  ct_def);
    fprintf(ct_def, "}\n\n");

    if (macro_qq) {
        fprintf(ct_decl, "declare ptr @malloc(i64)\n");
        fputs(k_qq_helpers, ct_def);
    }
    // Always declare nucleus_gensym so macro bodies can call (gensym).
    fprintf(ct_decl, "declare ptr @nucleus_gensym()\n");

    fclose(ct_decl);
    fclose(ct_def);

    // Assemble the macro JIT module IR.
    char  *ir_buf = NULL;
    size_t ir_sz  = 0;
    FILE  *irs    = open_memstream(&ir_buf, &ir_sz);
    fprintf(irs, "; ModuleID = '<defmacro %s>'\n", name);
    fprintf(irs, "target triple = \"x86_64-pc-linux-gnu\"\n\n");
    if (g_type_buf && g_type_buf[0]) fputs(g_type_buf, irs);
    emit_string_table(irs);
    if (g_decl_buf && g_decl_buf[0]) fputs(g_decl_buf, irs);
    if (ct_decl_buf && ct_decl_buf[0]) fputs(ct_decl_buf, irs);
    if (ct_def_buf  && ct_def_buf[0])  fputs(ct_def_buf,  irs);
    fclose(irs);

    jit_add_module(ir_buf, form->line);

    free(ct_decl_buf);
    free(ct_def_buf);
    free(ir_buf);
}

static Val emit_macro_call(Node *call, Scope *scope, int macro_idx) {
    static int depth = 0;
    if (depth >= 1024)
        die_at(call->line, "macro expansion limit exceeded (max 1024)");

    MacroDef *macro = &g_macros[macro_idx];
    int nargs = node_len(call) - 1;
    if (nargs != macro->num_params)
        die_at(call->line, "macro '%s': expected %d arg(s), got %d",
               macro->name, macro->num_params, nargs);

    // Look up the JIT function.
    LLVMOrcJITTargetAddress addr = 0;
    LLVMErrorRef err = LLVMOrcLLJITLookup(g_jit, &addr, macro->jit_name);
    if (err) {
        char *msg = LLVMGetErrorMessage(err);
        fprintf(stderr, "%s:%d: macro '%s': JIT lookup error: %s\n",
                g_source_path, call->line, macro->name, msg);
        LLVMDisposeErrorMessage(msg);
        exit(1);
    }
    if (!addr)
        die_at(call->line, "macro '%s': JIT function not found", macro->name);

    // Collect unevaluated argument nodes into a stack array.
    Node *args[8] = {NULL};
    for (int i = 0; i < nargs && i < 8; i++)
        args[i] = node_at(call, i + 1);

    // Call the macro function: ptr __macro_name(ptr args[])
    depth++;
    Node *result = ((Node *(*)(Node **))addr)(args);
    depth--;

    if (!result)
        die_at(call->line, "macro '%s': expansion returned NULL", macro->name);

    return emit_node(result, scope);
}

// ============================================================
// JIT implementation (LLVM ORC LLJIT) — called by emit_compile_time above
// ============================================================

static void jit_check(LLVMErrorRef err, int line, const char *msg) {
    if (!err) return;
    char *errmsg = LLVMGetErrorMessage(err);
    fprintf(stderr, "%s:%d: JIT error in %s: %s\n",
            g_source_path, line, msg, errmsg);
    LLVMDisposeErrorMessage(errmsg);
    exit(1);
}

static void jit_ensure_init(int line) {
    if (g_jit) return;
    LLVMInitializeNativeTarget();
    LLVMInitializeNativeAsmPrinter();
    LLVMErrorRef err = LLVMOrcCreateLLJIT(&g_jit, NULL);
    jit_check(err, line, "LLVMOrcCreateLLJIT");
    g_jit_dylib = LLVMOrcLLJITGetMainJITDylib(g_jit);
    char prefix = LLVMOrcLLJITGetGlobalPrefix(g_jit);
    LLVMOrcDefinitionGeneratorRef gen = NULL;
    err = LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess(&gen, prefix, NULL, NULL);
    jit_check(err, line, "LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess");
    LLVMOrcJITDylibAddGenerator(g_jit_dylib, gen);
}

static void jit_add_module(const char *ir, int line) {
    jit_ensure_init(line);
    // LLVMOrcThreadSafeContextGetContext was removed in LLVM 20+. Create the
    // parsing context directly; tsctx is only used for ThreadSafeModule locking
    // which is irrelevant in our single-threaded compiler. ctx leaks, which is
    // fine for a compiler process.
    LLVMContextRef ctx = LLVMContextCreate();
    LLVMMemoryBufferRef mb =
        LLVMCreateMemoryBufferWithMemoryRangeCopy(ir, strlen(ir), "<compile-time>");
    LLVMModuleRef mod = NULL;
    char *errmsg = NULL;
    if (LLVMParseIRInContext(ctx, mb, &mod, &errmsg))
        die_at(line, "compile-time: IR parse error: %s", errmsg ? errmsg : "(null)");
    LLVMOrcThreadSafeContextRef tsctx = LLVMOrcCreateNewThreadSafeContext();
    LLVMOrcThreadSafeModuleRef tsmod = LLVMOrcCreateNewThreadSafeModule(mod, tsctx);
    LLVMOrcDisposeThreadSafeContext(tsctx);
    LLVMErrorRef err = LLVMOrcLLJITAddLLVMIRModule(g_jit, g_jit_dylib, tsmod);
    jit_check(err, line, "LLVMOrcLLJITAddLLVMIRModule");
}

static void jit_call_ct_main_sym(int line, const char *sym) {
    (void)line;
    LLVMOrcJITTargetAddress addr = 0;
    LLVMErrorRef err = LLVMOrcLLJITLookup(g_jit, &addr, sym);
    if (err) { LLVMConsumeError(err); return; } // symbol not found — OK
    if (!addr) return;
    // Redirect stdout → stderr so CT printf output doesn't contaminate the IR
    // output written to stdout after compilation finishes.
    fflush(stdout);
    int saved_fd1 = dup(1);
    dup2(2, 1);
    ((void(*)(void))addr)();
    fflush(stdout);
    dup2(saved_fd1, 1);
    close(saved_fd1);
}

// ------------------------------------------------------------
// String table emission
// ------------------------------------------------------------

static void emit_string_table(FILE *out) {
    for (int i = 0; i < g_strs_len; i++) {
        int ir_len = g_strs[i].len + 1;
        fprintf(out, "@.str.%d = private unnamed_addr constant [%d x i8] c\"",
                g_strs[i].id, ir_len);
        for (int j = 0; j < g_strs[i].len; j++) {
            unsigned char c = (unsigned char)g_strs[i].bytes[j];
            if (c == '\\' || c == '"' || c < 0x20 || c >= 0x7f) {
                fprintf(out, "\\%02X", c);
            } else {
                fputc(c, out);
            }
        }
        fprintf(out, "\\00\", align 1\n");
    }
    if (g_strs_len) fputc('\n', out);
}

// ------------------------------------------------------------
// Driver
// ------------------------------------------------------------

static char *read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); exit(1); }
    if (fseek(f, 0, SEEK_END) != 0) { perror("fseek"); exit(1); }
    long sz = ftell(f);
    if (sz < 0) { perror("ftell"); exit(1); }
    rewind(f);
    char *buf = malloc((size_t)sz + 1);
    if (!buf) { perror("malloc"); exit(1); }
    size_t nr = fread(buf, 1, (size_t)sz, f);
    buf[nr] = 0;
    fclose(f);
    return buf;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: nucleusc <file.nuc>\n");
        return 2;
    }
    g_source_path = argv[1];
    char *src = read_file(argv[1]);

    arena_init();
    types_init();
    lex_init(src);

    Node *forms = read_program();

    g_globals = scope_new(NULL);

    // Buffer type defs, declares, and defines separately so we can emit:
    //   header -> type defs -> string table -> declares -> defines
    // Use global stream/buf vars so emit_compile_time can access them.
    g_type_buf = NULL; g_type_sz = 0;
    g_decl_buf = NULL; g_decl_sz = 0;
    g_def_buf  = NULL; g_def_sz  = 0;
    g_type_stream = open_memstream(&g_type_buf, &g_type_sz);
    g_decl_stream = open_memstream(&g_decl_buf, &g_decl_sz);
    g_def_stream  = open_memstream(&g_def_buf,  &g_def_sz);
    if (!g_type_stream || !g_decl_stream || !g_def_stream) {
        perror("open_memstream");
        return 1;
    }
    g_decl_out = g_decl_stream;

    // Pre-scan: register all defn signatures so forward/mutual recursion works.
    for (Node *fc = forms; fc; fc = fc->cdr) {
        Node *f = fc->car;
        if (!f || f->kind != NODE_CELL || node_len(f) < 4 ||
            node_at(f, 0)->kind != NODE_SYM ||
            strcmp(node_at(f, 0)->s, "defn") != 0)
            continue;
        Node *name_node = node_at(f, 1);
        Node *params_node = node_at(f, 2);
        if (name_node->kind != NODE_SYM || !node_is_list(params_node))
            continue;
        char *fname, *ret_name;
        split_typed(name_node->s, &fname, &ret_name);
        if (!ret_name) continue;
        Type *ret = parse_type_name(ret_name, name_node->line);
        int nparams = node_len(params_node);
        Type **ptypes = nparams
            ? arena_alloc((size_t)nparams * sizeof(Type *)) : NULL;
        for (int j = 0; j < nparams; j++) {
            Node *p = node_at(params_node, j);
            if (p->kind != NODE_SYM) continue;
            char *pn, *pt;
            split_typed(p->s, &pn, &pt);
            ptypes[j] = pt ? parse_type_name(pt, p->line) : ty_i32;
        }
        Type *ft = make_type(TY_FN);
        ft->ret = ret;
        ft->num_params = nparams;
        ft->params = ptypes;
        scope_define(g_globals, fname, ft,
                     arena_printf("@%s", fname), false);
    }

    for (Node *fc = forms; fc; fc = fc->cdr) {
        Node *f = fc->car;
        if (!f || f->kind != NODE_CELL || node_at(f, 0) == NULL || node_at(f, 0)->kind != NODE_SYM)
            die_at(f ? f->line : 0, "top-level form must be a list starting with a symbol");
        const char *h = node_at(f, 0)->s;
        if (strcmp(h, "defconst") == 0) {
            emit_defconst(f);
        } else if (strcmp(h, "defenum") == 0) {
            emit_defenum(f);
        } else if (strcmp(h, "defvar") == 0) {
            g_out = g_decl_stream;
            emit_defvar(f);
        } else if (strcmp(h, "defstruct") == 0) {
            g_out = g_type_stream;
            emit_defstruct(f);
        } else if (strcmp(h, "include") == 0) {
            g_out = g_decl_stream;
            emit_include(f);
        } else if (strcmp(h, "extern") == 0) {
            g_out = g_decl_stream;
            emit_extern(f);
        } else if (strcmp(h, "defn") == 0) {
            g_out = g_def_stream;
            emit_defn(f);
        } else if (strcmp(h, "compile-time") == 0) {
            emit_compile_time(f);
        } else if (strcmp(h, "defmacro") == 0) {
            emit_defmacro(f);
        } else {
            die_at(f->line, "unknown top-level form: %s", h);
        }
    }
    if (g_qq_used) {
        // Runtime helpers for quasiquote. Match lib/list.nuc cons semantics.
        fprintf(g_decl_stream, "declare ptr @malloc(i64)\n");
        fprintf(g_def_stream,
            "define ptr @__cons(ptr %%a, ptr %%b) {\n"
            "  %%c = call ptr @malloc(i64 40)\n"
            "  %%p0 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 0\n"
            "  store i32 3, ptr %%p0, align 8\n"
            "  %%p1 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 1\n"
            "  store i32 0, ptr %%p1, align 4\n"
            "  %%p2 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 2\n"
            "  store i64 0, ptr %%p2, align 8\n"
            "  %%p3 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 3\n"
            "  store ptr null, ptr %%p3, align 8\n"
            "  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 4\n"
            "  store ptr %%a, ptr %%p4, align 8\n"
            "  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 5\n"
            "  store ptr %%b, ptr %%p5, align 8\n"
            "  ret ptr %%c\n"
            "}\n\n"
            "define ptr @__append(ptr %%a, ptr %%b) {\n"
            "entry:\n"
            "  %%z = icmp eq ptr %%a, null\n"
            "  br i1 %%z, label %%nil, label %%rec\n"
            "nil:\n"
            "  ret ptr %%b\n"
            "rec:\n"
            "  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 4\n"
            "  %%car = load ptr, ptr %%p4, align 8\n"
            "  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 5\n"
            "  %%cdr = load ptr, ptr %%p5, align 8\n"
            "  %%rest = call ptr @__append(ptr %%cdr, ptr %%b)\n"
            "  %%c = call ptr @__cons(ptr %%car, ptr %%rest)\n"
            "  ret ptr %%c\n"
            "}\n\n");
    }
    fclose(g_type_stream);
    fclose(g_decl_stream);
    fclose(g_def_stream);

    printf("; ModuleID = '%s'\n", argv[1]);
    printf("source_filename = \"%s\"\n", argv[1]);
    printf("target triple = \"x86_64-pc-linux-gnu\"\n\n");
    if (g_type_buf && g_type_buf[0]) fputs(g_type_buf, stdout);
    emit_string_table(stdout);
    if (g_decl_buf && g_decl_buf[0]) fputs(g_decl_buf, stdout);
    if (g_def_buf  && g_def_buf[0])  fputs(g_def_buf,  stdout);

    free(g_type_buf);
    free(g_decl_buf);
    free(g_def_buf);
    return 0;
}
