#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"
#include "string.h"
#include "allocator.h"

/* Generated from lib/read.nuc by nucleusc --emit-cheader */

typedef struct ReadError {
    int32_t code;
    int32_t line;
    struct StrView msg;
    struct StrView note;
} ReadError;

int32_t read_error_code(struct ReadError e) asm("read-error-code");
typedef struct ReadResult {
    int32_t tag;
    union {
        void* ok;
        struct ReadError err;
    } payload;
} ReadResult;

enum ReadResult_tag {
    ReadResult_ok = 0,
    ReadResult_err = 1
};

struct ReadError rd_error(int32_t code, int32_t line, struct StrView msg, struct StrView note) asm("rd-error");
struct StrView rd_arena_str(struct String* s) asm("rd-arena-str");
typedef struct RMacro {
    struct StrView prefix;
    struct Symbol wrap;
} RMacro;

extern struct AllocHandle g_read_alloc asm("g-read-alloc");
#ifndef NUC_INST_Vector_RMacro
#define NUC_INST_Vector_RMacro
typedef struct Vector_RMacro {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct AllocHandle alloc;
} Vector_RMacro;
#endif

void rd_macro_add(struct Vector_RMacro* tbl, struct StrView prefix, struct Symbol wrap) asm("rd-macro-add");
int32_t rd_macro_find(struct Vector_RMacro* tbl, struct StrView prefix) asm("rd-macro-find");
struct Vector_RMacro* read_macro_table_new(void) asm("read-macro-table-new");
typedef struct Reader {
    struct StrView src;
    size_t pos;
    int32_t line;
    int32_t paren_depth;
    int32_t form_open_line;
    int32_t col0_open_line;
    int32_t col0_open_depth;
    struct Vector_RMacro* macros;
} Reader;

struct Reader reader_with_macros(struct StrView src, struct Vector_RMacro* table) asm("reader-with-macros");
struct Reader reader(struct StrView src);
int32_t rd_at(struct Reader* self, size_t i) asm("rd-at");
int32_t rd_peek(struct Reader* self) asm("rd-peek");
int32_t rd_peek1(struct Reader* self) asm("rd-peek1");
int32_t rd_next(struct Reader* self) asm("rd-next");
void rd_open_bracket(struct Reader* self, int32_t line, bool is_paren) asm("rd-open-bracket");
void rd_close_bracket(struct Reader* self) asm("rd-close-bracket");
struct ReadError rd_unterminated(struct Reader* self, int32_t open_line, struct StrView msg, struct StrView closer) asm("rd-unterminated");
bool rd_space_QMARK(int32_t c) asm("rd-space_QMARK");
bool rd_digit_QMARK(int32_t c) asm("rd-digit_QMARK");
int32_t rd_hex_val(int32_t c) asm("rd-hex-val");
void rd_skip_ws(struct Reader* self) asm("rd-skip-ws");
bool rd_sym_char_QMARK(int32_t c) asm("rd-sym-char_QMARK");
struct StrView rd_slice(struct Reader* self, size_t start) asm("rd-slice");
int32_t rd_tv_at(struct StrView* tv, size_t i) asm("rd-tv-at");
bool rd_int_atom_QMARK(struct StrView* tv) asm("rd-int-atom_QMARK");
int32_t rd_hex_kind(struct StrView* tv) asm("rd-hex-kind");
bool rd_float_atom_QMARK(struct StrView* tv) asm("rd-float-atom_QMARK");
/* rd-int-value: uses an error-union or option type; not exported */
int32_t rd_seg_next(int32_t c, int32_t seg) asm("rd-seg-next");
bool rd_legacy_marker_QMARK(struct StrView sv) asm("rd-legacy-marker_QMARK");
struct Symbol rd_expand_sigil(struct StrView tv) asm("rd-expand-sigil");
bool rd_at_legacy_marker(struct Reader* self) asm("rd-at-legacy-marker");
struct Node* rd_node(int32_t kind, int32_t line) asm("rd-node");
struct ReadResult rd_string(struct Reader* self, int32_t open_line, bool is_cstr) asm("rd-string");
struct Node* rd_char_node(int32_t cp, int32_t line) asm("rd-char-node");
struct ReadResult rd_char(struct Reader* self, int32_t open_line) asm("rd-char");
struct ReadResult rd_int_node(struct StrView tv, int32_t radix, int32_t line) asm("rd-int-node");
struct ReadResult rd_atom(struct Reader* self) asm("rd-atom");
int32_t rd_macro_match(struct Reader* self) asm("rd-macro-match");
bool rd_atom_start_QMARK(int32_t c) asm("rd-atom-start_QMARK");
struct ReadResult reader_register_macro(struct Reader* self, struct StrView prefix, struct Symbol wrap, int32_t line) asm("reader-register-macro");
bool rd_def_rmacro_form_QMARK(void* form) asm("rd-def-rmacro-form_QMARK");
struct ReadResult rd_def_rmacro(struct Reader* self, void* form) asm("rd-def-rmacro");
bool rd_fn_type_form_QMARK(void* form) asm("rd-fn-type-form_QMARK");
struct ReadResult rd_fuse_fn_params(struct Reader* self, void* paren_form, int32_t line) asm("rd-fuse-fn-params");
bool rd_open_segment_QMARK(struct StrView sv) asm("rd-open-segment_QMARK");
struct ReadResult rd_fuse_colon_paren(struct Reader* self, void* child, int32_t line) asm("rd-fuse-colon-paren");
struct ReadResult rd_list(struct Reader* self, int32_t open_line) asm("rd-list");
struct ReadResult rd_lit_elems(struct Reader* self, struct StrView what, int32_t closer, int32_t open_line) asm("rd-lit-elems");
void* rd_lit_cell(struct StrView name, void* elems, int32_t line) asm("rd-lit-cell");
struct ReadResult rd_atom_form(struct Reader* self, int32_t line) asm("rd-atom-form");
struct ReadResult rd_form(struct Reader* self) asm("rd-form");
bool reader_eof_QMARK(struct Reader* self) asm("reader-eof_QMARK");
struct ReadResult read_one(struct Reader* self) asm("read-one");
struct ReadResult read_all_with_macros(struct StrView src, struct Vector_RMacro* table) asm("read-all-with-macros");
struct ReadResult read_all(struct StrView src) asm("read-all");
void rd_write_escaped(struct String* out, struct StrView sv) asm("rd-write-escaped");
void rd_write_hex(struct String* out, uint64_t v) asm("rd-write-hex");
void sexp_write_string(struct String* out, struct StrView sv) asm("sexp-write-string");
void node_write(struct String* out, void* n) asm("node-write");
struct String node_str(void* n) asm("node-str");
bool node_eq(void* a, void* b) asm("node-eq");
