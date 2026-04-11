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
    TY_I32,
    TY_I8PTR,
    TY_FN,
} TypeKind;

typedef struct Type {
    TypeKind       kind;
    struct Type   *ret;
    struct Type  **params;
    int            num_params;
    bool           variadic;
} Type;

static Type *ty_void, *ty_i1, *ty_i32, *ty_i8ptr;

static Type *make_type(TypeKind k) {
    Type *t = arena_alloc(sizeof(Type));
    t->kind = k;
    return t;
}

static void types_init(void) {
    ty_void  = make_type(TY_VOID);
    ty_i1    = make_type(TY_I1);
    ty_i32   = make_type(TY_I32);
    ty_i8ptr = make_type(TY_I8PTR);
}

static const char *type_to_ir(Type *t) {
    switch (t->kind) {
        case TY_VOID:  return "void";
        case TY_I1:    return "i1";
        case TY_I32:   return "i32";
        case TY_I8PTR: return "ptr";
        case TY_FN:    return "<fn>";
    }
    return "?";
}

static Type *parse_type_name(const char *name, int line) {
    if (strcmp(name, "int") == 0) return ty_i32;
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
    Val v = { ty_i8ptr, tmp };
    return v;
}

static Val emit_symbol_ref(Node *n, Scope *scope) {
    Sym *sym = scope_lookup(scope, n->s);
    if (!sym) die_at(n->line, "undefined: %s", n->s);
    if (!sym->is_local) die_at(n->line, "cannot use function '%s' as value", n->s);
    const char *tmp = new_tmp();
    body_emit("  %s = load %s, ptr %s, align 4\n",
              tmp, type_to_ir(sym->type), sym->ir_name);
    Val v = { sym->type, tmp };
    return v;
}

static Val emit_builtin_lt(Node *call, Scope *scope) {
    if (call->len != 3) die_at(call->line, "< expects 2 args");
    Val a = emit_node(call->items[1], scope);
    Val b = emit_node(call->items[2], scope);
    if (a.type->kind != TY_I32 || b.type->kind != TY_I32)
        die_at(call->line, "< expects i32 operands");
    const char *tmp = new_tmp();
    body_emit("  %s = icmp slt i32 %s, %s\n", tmp, a.val, b.val);
    Val v = { ty_i1, tmp };
    return v;
}

static Val emit_builtin_mul(Node *call, Scope *scope) {
    if (call->len != 3) die_at(call->line, "* expects 2 args");
    Val a = emit_node(call->items[1], scope);
    Val b = emit_node(call->items[2], scope);
    if (a.type->kind != TY_I32 || b.type->kind != TY_I32)
        die_at(call->line, "* expects i32 operands");
    const char *tmp = new_tmp();
    body_emit("  %s = mul nsw i32 %s, %s\n", tmp, a.val, b.val);
    Val v = { ty_i32, tmp };
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
        entry_emit("  %s = alloca %s, align 4\n", slot, type_to_ir(ty));

        Val v = emit_node(bval, inner);
        if (v.type->kind != ty->kind)
            die_at(bval->line, "let: init type mismatch for '%s'", name);
        body_emit("  store %s %s, ptr %s, align 4\n",
                  type_to_ir(ty), v.val, slot);

        scope_define(inner, name, ty, slot, true);
    }
    Val last = { ty_void, NULL };
    for (int i = 2; i < call->len; i++) {
        last = emit_node(call->items[i], inner);
    }
    return last;
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
    body_emit("  store %s %s, ptr %s, align 4\n",
              type_to_ir(sym->type), v.val, sym->ir_name);
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
    if (sym->type->kind != TY_I32)
        die_at(call->line, "inc!: must be int");
    const char *t1 = new_tmp();
    body_emit("  %s = load i32, ptr %s, align 4\n", t1, sym->ir_name);
    const char *t2 = new_tmp();
    body_emit("  %s = add nsw i32 %s, 1\n", t2, t1);
    body_emit("  store i32 %s, ptr %s, align 4\n", t2, sym->ir_name);
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
    if (strcmp(h, "while")  == 0) return emit_while(n, scope);
    if (strcmp(h, "set!")   == 0) return emit_set(n, scope);
    if (strcmp(h, "inc!")   == 0) return emit_inc(n, scope);
    if (strcmp(h, "<")      == 0) return emit_builtin_lt(n, scope);
    if (strcmp(h, "*")      == 0) return emit_builtin_mul(n, scope);

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

static void emit_include(Node *call) {
    if (call->len != 2 || call->items[1]->kind != NODE_SYM)
        die_at(call->line, "include: expects one symbol");
    const char *name = call->items[1]->s;
    if (strcmp(name, "stdio") == 0) {
        Type *ft = make_type(TY_FN);
        ft->ret = ty_i32;
        ft->num_params = 1;
        ft->params = arena_alloc(sizeof(Type *));
        ft->params[0] = ty_i8ptr;
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

    if (params_node->len != 0)
        die_at(params_node->line, "defn: params not yet supported");

    reset_function_state();
    Scope *fn_scope = scope_new(g_globals);

    for (int i = 3; i < call->len; i++) {
        emit_node(call->items[i], fn_scope);
    }
    if (!g_block_term) {
        if (ret->kind == TY_VOID) body_emit("  ret void\n");
        else body_emit("  ret %s 0\n", type_to_ir(ret));
    }

    fprintf(g_out, "define %s @%s() {\n", type_to_ir(ret), fname);
    fprintf(g_out, "entry:\n");
    if (g_entry_buf && g_entry_buf[0]) fputs(g_entry_buf, g_out);
    if (g_body_buf  && g_body_buf[0])  fputs(g_body_buf,  g_out);
    fprintf(g_out, "}\n\n");

    Type *ft = make_type(TY_FN);
    ft->ret = ret;
    scope_define(g_globals, fname, ft, arena_printf("@%s", fname), false);
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

    // Buffer declares and defines separately so we can emit:
    //   header -> string table -> declares -> defines
    char  *decl_buf = NULL;  size_t decl_size = 0;
    char  *def_buf  = NULL;  size_t def_size  = 0;
    FILE  *decl_stream = open_memstream(&decl_buf, &decl_size);
    FILE  *def_stream  = open_memstream(&def_buf,  &def_size);
    if (!decl_stream || !def_stream) {
        perror("open_memstream");
        return 1;
    }

    for (int i = 0; i < nforms; i++) {
        Node *f = forms[i];
        if (f->kind != NODE_LIST || f->len == 0 || f->items[0]->kind != NODE_SYM)
            die_at(f->line, "top-level form must be a list starting with a symbol");
        const char *h = f->items[0]->s;
        if (strcmp(h, "include") == 0) {
            g_out = decl_stream;
            emit_include(f);
        } else if (strcmp(h, "defn") == 0) {
            g_out = def_stream;
            emit_defn(f);
        } else {
            die_at(f->line, "unknown top-level form: %s", h);
        }
    }
    fclose(decl_stream);
    fclose(def_stream);

    printf("; ModuleID = '%s'\n", argv[1]);
    printf("source_filename = \"%s\"\n", argv[1]);
    printf("target triple = \"x86_64-pc-linux-gnu\"\n\n");
    emit_string_table(stdout);
    if (decl_buf && decl_buf[0]) fputs(decl_buf, stdout);
    if (def_buf  && def_buf[0])  fputs(def_buf,  stdout);

    free(decl_buf);
    free(def_buf);
    return 0;
}
