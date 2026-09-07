#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"
#include "string.h"

/* Generated from lib/read.nuc by nucleusc --emit-cheader */

typedef struct Reader {
    struct StrView src;
    size_t pos;
    int32_t line;
    int32_t err_line;
} Reader;

struct Reader reader(struct StrView src);
int32_t reader_error_line(struct Reader* self) asm("reader-error-line");
void rd_fail(struct Reader* self, int32_t line) asm("rd-fail");
int32_t rd_at(struct Reader* self, size_t i) asm("rd-at");
int32_t rd_peek(struct Reader* self) asm("rd-peek");
int32_t rd_peek1(struct Reader* self) asm("rd-peek1");
int32_t rd_next(struct Reader* self) asm("rd-next");
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
void* rd_string(struct Reader* self, int32_t open_line, bool is_cstr) asm("rd-string");
struct Node* rd_char_node(int32_t cp, int32_t line) asm("rd-char-node");
void* rd_char(struct Reader* self, int32_t open_line) asm("rd-char");
void* rd_atom(struct Reader* self) asm("rd-atom");
struct StrView rd_macro_name(struct Reader* self) asm("rd-macro-name");
int32_t rd_macro_len(struct StrView name) asm("rd-macro-len");
bool rd_fn_type_form_QMARK(void* form) asm("rd-fn-type-form_QMARK");
void* rd_fuse_fn_params(struct Reader* self, void* paren_form, int32_t line) asm("rd-fuse-fn-params");
void* rd_fuse_colon_paren(struct Reader* self, void* child, int32_t line) asm("rd-fuse-colon-paren");
void* rd_list(struct Reader* self, int32_t open_line) asm("rd-list");
void* rd_form(struct Reader* self) asm("rd-form");
bool reader_eof_QMARK(struct Reader* self) asm("reader-eof_QMARK");
void* read_one(struct Reader* self) asm("read-one");
void* read_all(struct StrView src) asm("read-all");
void rd_write_escaped(struct String* out, struct StrView sv) asm("rd-write-escaped");
void rd_write_hex(struct String* out, uint64_t v) asm("rd-write-hex");
void sexp_write_string(struct String* out, struct StrView sv) asm("sexp-write-string");
void node_write(struct String* out, void* n) asm("node-write");
struct String node_str(void* n) asm("node-str");
bool node_eq(void* a, void* b) asm("node-eq");
