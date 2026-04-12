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
    NODE_LIST,
} NodeKind;

typedef struct Node {
    NodeKind       kind;
    int            line;
    long           i;    // NODE_INT
    char          *s;    // NODE_STR, NODE_SYM
    struct Node  **items;
    int            len;  // NODE_LIST
} Node;

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

static void push_node(Node ***items, int *len, int *cap, Node *n) {
    if (*len == *cap) {
        int nc = *cap ? *cap * 2 : 4;
        Node **ni = arena_alloc((size_t)nc * sizeof(Node *));
        for (int i = 0; i < *len; i++) ni[i] = (*items)[i];
        *items = ni;
        *cap = nc;
    }
    (*items)[(*len)++] = n;
}

static Node *read_list(int line) {
    Node **items = NULL;
    int len = 0, cap = 0;
    for (;;) {
        Tok t = peek_tok();
        if (t.kind == TOK_EOF) die_at(line, "unterminated list");
        if (t.kind == TOK_RPAREN) { eat_tok(); break; }
        Node *child = read_form();
        push_node(&items, &len, &cap, child);
    }
    Node *n = arena_alloc(sizeof(Node));
    n->kind = NODE_LIST;
    n->line = line;
    n->items = items;
    n->len = len;
    return n;
}

static Node *read_form(void) {
    Tok t = eat_tok();
    Node *n;
    switch (t.kind) {
        case TOK_LPAREN: return read_list(t.line);
        case TOK_RPAREN: die_at(t.line, "unexpected )");
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

static Node **read_program(int *out_len) {
    Node **forms = NULL;
    int len = 0, cap = 0;
    while (peek_tok().kind != TOK_EOF) {
        push_node(&forms, &len, &cap, read_form());
    }
    *out_len = len;
    return forms;
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
    const char *ir_name;  // "%i.addr" for locals, "@printf" for globals
    bool        is_local;
} Sym;

typedef struct Scope {
    struct Scope *parent;
    Sym          *syms;
    int           len, cap;
} Scope;

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
static Scope *g_globals;

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

static Val emit_int(Node *n) {
    Val v = { ty_i32, arena_printf("%ld", n->i) };
    return v;
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
    if (call->len != 3)
        die_at(call->line, "%s expects 2 args", op->name);
    Val a = emit_node(call->items[1], scope);
    Val b = emit_node(call->items[2], scope);
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
    if (call->len != 3) die_at(call->line, "cast expects 2 args");
    Node *type_node = call->items[1];
    if (type_node->kind != NODE_SYM)
        die_at(type_node->line, "cast: target type must be a symbol");
    Type *dst = parse_type_name(type_node->s, type_node->line);
    Val v = emit_node(call->items[2], scope);
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
    if (call->len != 3) die_at(call->line, ". expects 2 args");
    Val p = emit_node(call->items[1], scope);
    if (p.type->kind != TY_PTR || !p.type->elem ||
        p.type->elem->kind != TY_STRUCT)
        die_at(call->line, ".: operand must be pointer to struct");
    Node *fn = call->items[2];
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
    if (call->len != 4) die_at(call->line, ".set! expects 3 args");
    Val p = emit_node(call->items[1], scope);
    if (p.type->kind != TY_PTR || !p.type->elem ||
        p.type->elem->kind != TY_STRUCT)
        die_at(call->line, ".set!: operand must be pointer to struct");
    Node *fn = call->items[2];
    if (fn->kind != NODE_SYM) die_at(fn->line, ".set!: field name must be symbol");
    StructDef *sd = p.type->elem->sdef;
    int idx = -1;
    for (int i = 0; i < sd->num_fields; i++) {
        if (strcmp(sd->field_names[i], fn->s) == 0) { idx = i; break; }
    }
    if (idx < 0) die_at(fn->line, ".set!: no field '%s' on struct '%s'",
                        fn->s, sd->name);
    Type *ftype = sd->field_types[idx];
    Val v = emit_node(call->items[3], scope);
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
    if (call->len != 2) die_at(call->line, "sizeof expects 1 arg");
    Node *tn = call->items[1];
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

// (alloca TypeName) — stack-allocate and return typed pointer
static Val emit_alloca_form(Node *call, Scope *scope) {
    (void)scope;
    if (call->len != 2) die_at(call->line, "alloca expects 1 arg");
    Node *tn = call->items[1];
    if (tn->kind != NODE_SYM) die_at(tn->line, "alloca: arg must be type name");
    Type *ty = parse_type_name(tn->s, tn->line);
    const char *slot = new_tmp();
    entry_emit("  %s = alloca %s, align %d\n",
               slot, type_to_ir(ty), type_align(ty));
    Type *pt = make_type(TY_PTR);
    pt->elem = ty;
    Val r = { pt, slot };
    return r;
}

static Val emit_addr_of(Node *call, Scope *scope) {
    if (call->len != 2) die_at(call->line, "addr-of expects 1 arg");
    Node *target = call->items[1];
    if (target->kind != NODE_SYM)
        die_at(target->line, "addr-of: target must be symbol");
    Sym *sym = scope_lookup(scope, target->s);
    if (!sym || !sym->is_local)
        die_at(target->line, "addr-of: undefined local '%s'", target->s);
    Type *pt = make_type(TY_PTR);
    pt->elem = sym->type;
    Val r = { pt, sym->ir_name };
    return r;
}

static Val emit_deref(Node *call, Scope *scope) {
    if (call->len != 2) die_at(call->line, "deref expects 1 arg");
    Val p = emit_node(call->items[1], scope);
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
    if (call->len != 3) die_at(call->line, "ptr-set! expects 2 args");
    Val p = emit_node(call->items[1], scope);
    if (p.type->kind != TY_PTR || !p.type->elem)
        die_at(call->line, "ptr-set!: operand must be typed pointer");
    Type *elem = p.type->elem;
    Val v = emit_node(call->items[2], scope);
    if (v.type->kind != elem->kind)
        die_at(call->line, "ptr-set!: value type mismatch");
    body_emit("  store %s %s, ptr %s, align %d\n",
              type_to_ir(elem), v.val, p.val, type_align(elem));
    Val r = { ty_void, NULL };
    return r;
}

static Val emit_ptr_add(Node *call, Scope *scope) {
    if (call->len != 3) die_at(call->line, "ptr+ expects 2 args");
    Val p = emit_node(call->items[1], scope);
    if (p.type->kind != TY_PTR || !p.type->elem)
        die_at(call->line, "ptr+: operand must be typed pointer");
    Val n = emit_node(call->items[2], scope);
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
    if (call->len != 2) die_at(call->line, "not expects 1 arg");
    Val a = emit_node(call->items[1], scope);
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
    if (call->len != 3)
        die_at(call->line, "%s expects 2 args", is_and ? "and" : "or");
    int id = new_label_id();
    const char *rhs_lbl = arena_printf("%s.rhs%d", is_and ? "and" : "or", id);
    const char *end_lbl = arena_printf("%s.end%d", is_and ? "and" : "or", id);
    const char *slot    = arena_printf("%%%s.val%d", is_and ? "and" : "or", id);

    entry_emit("  %s = alloca i1, align 1\n", slot);

    Val lhs = emit_node(call->items[1], scope);
    if (lhs.type->kind != TY_I1)
        die_at(call->items[1]->line,
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
    Val rhs = emit_node(call->items[2], scope);
    if (rhs.type->kind != TY_I1)
        die_at(call->items[2]->line,
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
    int nargs = call->len - 1;
    Val *args = arena_alloc((size_t)nargs * sizeof(Val));
    for (int i = 0; i < nargs; i++) {
        args[i] = emit_node(call->items[i + 1], scope);
    }
    // Build comma-separated argument list
    char arglist[2048];
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
    if (call->len != 2) die_at(call->line, "return expects 1 arg");
    Val v = emit_node(call->items[1], scope);
    body_emit("  ret %s %s\n", type_to_ir(v.type), v.val);
    g_block_term = true;
    Val r = { ty_void, NULL };
    return r;
}

static Val emit_let(Node *call, Scope *scope) {
    // (let (name:type val ...) body...)
    if (call->len < 2 || call->items[1]->kind != NODE_LIST)
        die_at(call->line, "let: bad form");
    Node *binds = call->items[1];
    if (binds->len % 2 != 0)
        die_at(binds->line, "let: binding list must be even");

    Scope *inner = scope_new(scope);
    for (int i = 0; i < binds->len; i += 2) {
        Node *bname = binds->items[i];
        Node *bval  = binds->items[i + 1];
        if (bname->kind != NODE_SYM)
            die_at(bname->line, "let: binding name must be symbol");
        char *name, *type_name;
        split_typed(bname->s, &name, &type_name);
        if (!type_name)
            die_at(bname->line, "let: missing :type on '%s'", name);
        Type *ty = parse_type_name(type_name, bname->line);

        const char *slot = arena_printf("%%%s.addr", name);
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
    for (int i = 2; i < call->len; i++) {
        last = emit_node(call->items[i], inner);
    }
    return last;
}

static Val emit_if(Node *call, Scope *scope) {
    // (if cond then) or (if cond then else)
    if (call->len != 3 && call->len != 4)
        die_at(call->line, "if: expects 2 or 3 args");
    bool has_else = (call->len == 4);
    int id = new_label_id();
    const char *then_lbl = arena_printf("if.then%d", id);
    const char *else_lbl = arena_printf("if.else%d", id);
    const char *end_lbl  = arena_printf("if.end%d",  id);

    Val cond = emit_node(call->items[1], scope);
    if (cond.type->kind != TY_I1)
        die_at(call->items[1]->line, "if condition must be i1");
    body_emit("  br i1 %s, label %%%s, label %%%s\n",
              cond.val, then_lbl, has_else ? else_lbl : end_lbl);

    body_emit("%s:\n", then_lbl);
    g_block_term = false;
    emit_node(call->items[2], scope);
    if (!g_block_term) body_emit("  br label %%%s\n", end_lbl);

    if (has_else) {
        body_emit("%s:\n", else_lbl);
        g_block_term = false;
        emit_node(call->items[3], scope);
        if (!g_block_term) body_emit("  br label %%%s\n", end_lbl);
    }

    body_emit("%s:\n", end_lbl);
    g_block_term = false;
    Val r = { ty_void, NULL };
    return r;
}

static Val emit_while(Node *call, Scope *scope) {
    if (call->len < 2) die_at(call->line, "while: missing condition");
    int id = new_label_id();
    const char *cond_lbl = arena_printf("while.cond%d", id);
    const char *body_lbl = arena_printf("while.body%d", id);
    const char *end_lbl  = arena_printf("while.end%d",  id);

    body_emit("  br label %%%s\n", cond_lbl);
    body_emit("%s:\n", cond_lbl);
    g_block_term = false;
    Val cond = emit_node(call->items[1], scope);
    if (cond.type->kind != TY_I1)
        die_at(call->items[1]->line, "while condition must be i1");
    body_emit("  br i1 %s, label %%%s, label %%%s\n",
              cond.val, body_lbl, end_lbl);

    body_emit("%s:\n", body_lbl);
    g_block_term = false;
    for (int i = 2; i < call->len; i++) {
        emit_node(call->items[i], scope);
    }
    if (!g_block_term) body_emit("  br label %%%s\n", cond_lbl);

    body_emit("%s:\n", end_lbl);
    g_block_term = false;
    Val r = { ty_void, NULL };
    return r;
}

static Val emit_set(Node *call, Scope *scope) {
    if (call->len != 3) die_at(call->line, "set! expects 2 args");
    Node *target = call->items[1];
    if (target->kind != NODE_SYM)
        die_at(target->line, "set!: target must be symbol");
    Sym *sym = scope_lookup(scope, target->s);
    if (!sym || !sym->is_local)
        die_at(target->line, "set!: undefined local '%s'", target->s);
    Val v = emit_node(call->items[2], scope);
    if (v.type->kind != sym->type->kind)
        die_at(call->line, "set!: type mismatch for '%s'", target->s);
    body_emit("  store %s %s, ptr %s, align %d\n",
              type_to_ir(sym->type), v.val, sym->ir_name, type_align(sym->type));
    Val r = { ty_void, NULL };
    return r;
}

static Val emit_inc(Node *call, Scope *scope) {
    if (call->len != 2) die_at(call->line, "inc! expects 1 arg");
    Node *target = call->items[1];
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
    if (n->len == 0) die_at(n->line, "empty list");
    Node *head = n->items[0];
    if (head->kind != NODE_SYM) die_at(head->line, "list head must be symbol");
    const char *h = head->s;

    if (strcmp(h, "return") == 0) return emit_return(n, scope);
    if (strcmp(h, "let")    == 0) return emit_let(n, scope);
    if (strcmp(h, "if")     == 0) return emit_if(n, scope);
    if (strcmp(h, "while")  == 0) return emit_while(n, scope);
    if (strcmp(h, "set!")   == 0) return emit_set(n, scope);
    if (strcmp(h, "inc!")   == 0) return emit_inc(n, scope);
    if (strcmp(h, "not")     == 0) return emit_not(n, scope);
    if (strcmp(h, "and")     == 0) return emit_short_circuit(n, scope, true);
    if (strcmp(h, "or")      == 0) return emit_short_circuit(n, scope, false);
    if (strcmp(h, "cast")    == 0) return emit_cast(n, scope);
    if (strcmp(h, "addr-of") == 0) return emit_addr_of(n, scope);
    if (strcmp(h, "deref")   == 0) return emit_deref(n, scope);
    if (strcmp(h, "ptr-set!") == 0) return emit_ptr_set(n, scope);
    if (strcmp(h, "ptr+")    == 0) return emit_ptr_add(n, scope);
    if (strcmp(h, ".")       == 0) return emit_field_get(n, scope);
    if (strcmp(h, ".set!")   == 0) return emit_field_set(n, scope);
    if (strcmp(h, "sizeof")  == 0) return emit_sizeof(n, scope);
    if (strcmp(h, "alloca")  == 0) return emit_alloca_form(n, scope);

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
        case NODE_LIST: return emit_list(n, scope);
    }
    Val r = { ty_void, NULL };
    return r;
}

// ------------------------------------------------------------
// Top-level forms
// ------------------------------------------------------------

static void emit_defstruct(Node *call) {
    // (defstruct Name field1:type1 field2:type2 ...)
    if (call->len < 2) die_at(call->line, "defstruct: missing name");
    Node *name_node = call->items[1];
    if (name_node->kind != NODE_SYM)
        die_at(name_node->line, "defstruct: name must be symbol");
    StructDef *sd = register_struct(name_node->s);
    int nfields = call->len - 2;
    sd->field_names = arena_alloc((size_t)nfields * sizeof(char *));
    sd->field_types = arena_alloc((size_t)nfields * sizeof(Type *));
    sd->num_fields = nfields;
    for (int i = 0; i < nfields; i++) {
        Node *field = call->items[i + 2];
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

static void emit_include(Node *call) {
    if (call->len != 2 || call->items[1]->kind != NODE_SYM)
        die_at(call->line, "include: expects one symbol");
    const char *name = call->items[1]->s;
    if (strcmp(name, "stdio") == 0) {
        Type *ft = make_type(TY_FN);
        ft->ret = ty_i32;
        ft->num_params = 1;
        ft->params = arena_alloc(sizeof(Type *));
        ft->params[0] = ty_ptr;
        ft->variadic = true;
        scope_define(g_globals, "printf", ft, "@printf", false);
        fprintf(g_out, "declare i32 @printf(ptr, ...)\n\n");
        return;
    }
    die_at(call->line, "unknown include: %s", name);
}

static void emit_defn(Node *call) {
    // (defn name:type (params...) body...)
    if (call->len < 4) die_at(call->line, "defn: bad form");
    Node *name_node = call->items[1];
    Node *params_node = call->items[2];
    if (name_node->kind != NODE_SYM)
        die_at(name_node->line, "defn: name must be symbol");
    if (params_node->kind != NODE_LIST)
        die_at(params_node->line, "defn: params must be list");

    char *fname, *ret_name;
    split_typed(name_node->s, &fname, &ret_name);
    if (!ret_name) die_at(name_node->line, "defn: missing :type on '%s'", fname);
    Type *ret = parse_type_name(ret_name, name_node->line);

    int nparams = params_node->len;
    Type **param_types = NULL;
    char **param_names = NULL;
    if (nparams > 0) {
        param_types = arena_alloc((size_t)nparams * sizeof(Type *));
        param_names = arena_alloc((size_t)nparams * sizeof(char *));
    }
    for (int i = 0; i < nparams; i++) {
        Node *p = params_node->items[i];
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

    for (int i = 3; i < call->len; i++) {
        emit_node(call->items[i], fn_scope);
    }
    if (!g_block_term) {
        if (ret->kind == TY_VOID) body_emit("  ret void\n");
        else body_emit("  ret %s 0\n", type_to_ir(ret));
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

    int nforms;
    Node **forms = read_program(&nforms);

    g_globals = scope_new(NULL);

    // Buffer type defs, declares, and defines separately so we can emit:
    //   header -> type defs -> string table -> declares -> defines
    char  *type_buf = NULL;  size_t type_size = 0;
    char  *decl_buf = NULL;  size_t decl_size = 0;
    char  *def_buf  = NULL;  size_t def_size  = 0;
    FILE  *type_stream = open_memstream(&type_buf, &type_size);
    FILE  *decl_stream = open_memstream(&decl_buf, &decl_size);
    FILE  *def_stream  = open_memstream(&def_buf,  &def_size);
    if (!type_stream || !decl_stream || !def_stream) {
        perror("open_memstream");
        return 1;
    }

    for (int i = 0; i < nforms; i++) {
        Node *f = forms[i];
        if (f->kind != NODE_LIST || f->len == 0 || f->items[0]->kind != NODE_SYM)
            die_at(f->line, "top-level form must be a list starting with a symbol");
        const char *h = f->items[0]->s;
        if (strcmp(h, "defstruct") == 0) {
            g_out = type_stream;
            emit_defstruct(f);
        } else if (strcmp(h, "include") == 0) {
            g_out = decl_stream;
            emit_include(f);
        } else if (strcmp(h, "defn") == 0) {
            g_out = def_stream;
            emit_defn(f);
        } else {
            die_at(f->line, "unknown top-level form: %s", h);
        }
    }
    fclose(type_stream);
    fclose(decl_stream);
    fclose(def_stream);

    printf("; ModuleID = '%s'\n", argv[1]);
    printf("source_filename = \"%s\"\n", argv[1]);
    printf("target triple = \"x86_64-pc-linux-gnu\"\n\n");
    if (type_buf && type_buf[0]) fputs(type_buf, stdout);
    emit_string_table(stdout);
    if (decl_buf && decl_buf[0]) fputs(decl_buf, stdout);
    if (def_buf  && def_buf[0])  fputs(def_buf,  stdout);

    free(type_buf);
    free(decl_buf);
    free(def_buf);
    return 0;
}
