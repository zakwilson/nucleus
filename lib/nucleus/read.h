#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"
#include "string.h"
#include "allocator.h"

/* Generated from lib/nucleus/read.nuc by nucleusc --emit-cheader */

enum LitMark {
    LitMark_LIT_NONE = 0,
    LitMark_LIT_VECTOR = 1,
    LitMark_LIT_MAP = 2,
    LitMark_LIT_SET = 3,
    LitMark_LIT_TAGGED = 4
};

typedef struct nuc_ReadError {
    int32_t code;
    int32_t line;
    struct nuc_StrView msg;
    struct nuc_StrView note;
} nuc_ReadError;

int32_t nuc_read_error_code(struct nuc_ReadError e) asm("nuc_read-error-code");
typedef struct nuc_ReadResult {
    int32_t tag;
    union {
        struct nuc_Node* /* nullable */ ok;
        struct nuc_ReadError err;
    } payload;
} nuc_ReadResult;

enum nuc_ReadResult_tag {
    nuc_ReadResult_ok = 0,
    nuc_ReadResult_err = 1
};

struct nuc_ReadError nuc_rd_error(int32_t code, int32_t line, struct nuc_StrView msg, struct nuc_StrView note) asm("nuc_rd-error");
struct nuc_StrView nuc_rd_arena_str(struct nuc_String* s) asm("nuc_rd-arena-str");
typedef struct nuc_RMacro {
    struct nuc_StrView prefix;
    struct nuc_Symbol wrap;
} nuc_RMacro;

extern struct nuc_AllocHandle nuc_g_read_alloc asm("nuc_g-read-alloc");
#ifndef NUC_INST_nuc_Vector_nuc_RMacro
#define NUC_INST_nuc_Vector_nuc_RMacro
typedef struct nuc_Vector_nuc_RMacro {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_AllocHandle alloc;
} nuc_Vector_nuc_RMacro;
#endif

void nuc_rd_macro_add(struct nuc_Vector_nuc_RMacro* tbl, struct nuc_StrView prefix, struct nuc_Symbol wrap) asm("nuc_rd-macro-add");
int32_t nuc_rd_macro_find(struct nuc_Vector_nuc_RMacro* tbl, struct nuc_StrView prefix) asm("nuc_rd-macro-find");
struct nuc_Vector_nuc_RMacro* nuc_read_macro_table_new(void) asm("nuc_read-macro-table-new");
typedef struct nuc_Reader {
    struct nuc_StrView src;
    size_t pos;
    int32_t line;
    int32_t paren_depth;
    int32_t form_open_line;
    int32_t col0_open_line;
    int32_t col0_open_depth;
    struct nuc_Vector_nuc_RMacro* macros;
    bool edn;
} nuc_Reader;

struct nuc_Reader nuc_reader_with_macros(struct nuc_StrView src, struct nuc_Vector_nuc_RMacro* table) asm("nuc_reader-with-macros");
struct nuc_Reader nuc_reader(struct nuc_StrView src);
struct nuc_Reader nuc_reader_edn(struct nuc_StrView src) asm("nuc_reader-edn");
int32_t nuc_rd_at(struct nuc_Reader* self, size_t i) asm("nuc_rd-at");
int32_t nuc_rd_peek(struct nuc_Reader* self) asm("nuc_rd-peek");
int32_t nuc_rd_peek1(struct nuc_Reader* self) asm("nuc_rd-peek1");
int32_t nuc_rd_next(struct nuc_Reader* self) asm("nuc_rd-next");
void nuc_rd_open_bracket(struct nuc_Reader* self, int32_t line, bool is_paren) asm("nuc_rd-open-bracket");
void nuc_rd_close_bracket(struct nuc_Reader* self) asm("nuc_rd-close-bracket");
struct nuc_ReadError nuc_rd_unterminated(struct nuc_Reader* self, int32_t open_line, struct nuc_StrView msg, struct nuc_StrView closer) asm("nuc_rd-unterminated");
bool nuc_rd_space_QMARK(int32_t c) asm("nuc_rd-space_QMARK");
bool nuc_rd_digit_QMARK(int32_t c) asm("nuc_rd-digit_QMARK");
int32_t nuc_rd_hex_val(int32_t c) asm("nuc_rd-hex-val");
void nuc_rd_skip_ws(struct nuc_Reader* self) asm("nuc_rd-skip-ws");
bool nuc_rd_sym_char_QMARK(int32_t c) asm("nuc_rd-sym-char_QMARK");
struct nuc_StrView nuc_rd_slice(struct nuc_Reader* self, size_t start) asm("nuc_rd-slice");
int32_t nuc_rd_tv_at(struct nuc_StrView* tv, size_t i) asm("nuc_rd-tv-at");
bool nuc_rd_int_atom_QMARK(struct nuc_StrView* tv) asm("nuc_rd-int-atom_QMARK");
int32_t nuc_rd_hex_kind(struct nuc_StrView* tv) asm("nuc_rd-hex-kind");
bool nuc_rd_float_atom_QMARK(struct nuc_StrView* tv) asm("nuc_rd-float-atom_QMARK");
/* rd-int-value: uses an error-union or option type; not exported */
int32_t nuc_rd_seg_next(int32_t c, int32_t seg) asm("nuc_rd-seg-next");
bool nuc_rd_legacy_marker_QMARK(struct nuc_StrView sv) asm("nuc_rd-legacy-marker_QMARK");
struct nuc_Symbol nuc_rd_expand_sigil(struct nuc_StrView tv) asm("nuc_rd-expand-sigil");
bool nuc_rd_at_legacy_marker(struct nuc_Reader* self) asm("nuc_rd-at-legacy-marker");
struct nuc_Node* nuc_rd_node(int32_t kind, int32_t line) asm("nuc_rd-node");
int32_t nuc_rd_hex4(struct nuc_Reader* self) asm("nuc_rd-hex4");
bool nuc_rd_surrogate_QMARK(int32_t cp) asm("nuc_rd-surrogate_QMARK");
struct nuc_ReadResult nuc_rd_string(struct nuc_Reader* self, int32_t open_line, bool is_cstr) asm("nuc_rd-string");
struct nuc_Node* nuc_rd_char_node(int32_t cp, int32_t line) asm("nuc_rd-char-node");
struct nuc_ReadResult nuc_rd_char(struct nuc_Reader* self, int32_t open_line) asm("nuc_rd-char");
struct nuc_ReadResult nuc_rd_int_node(struct nuc_StrView tv, int32_t radix, int32_t line) asm("nuc_rd-int-node");
struct nuc_Node* nuc_rd_float_node(struct nuc_StrView tv, int32_t line) asm("nuc_rd-float-node");
struct nuc_ReadResult nuc_rd_edn_int(struct nuc_StrView tv, int32_t line) asm("nuc_rd-edn-int");
struct nuc_ReadResult nuc_rd_edn_atom(struct nuc_StrView tv, int32_t line) asm("nuc_rd-edn-atom");
struct nuc_ReadResult nuc_rd_atom(struct nuc_Reader* self) asm("nuc_rd-atom");
int32_t nuc_rd_macro_match(struct nuc_Reader* self) asm("nuc_rd-macro-match");
bool nuc_rd_atom_start_QMARK(int32_t c) asm("nuc_rd-atom-start_QMARK");
struct nuc_ReadResult nuc_reader_register_macro(struct nuc_Reader* self, struct nuc_StrView prefix, struct nuc_Symbol wrap, int32_t line) asm("nuc_reader-register-macro");
bool nuc_rd_def_rmacro_form_QMARK(struct nuc_Node* /* nullable */ form) asm("nuc_rd-def-rmacro-form_QMARK");
struct nuc_ReadResult nuc_rd_def_rmacro(struct nuc_Reader* self, struct nuc_Node* form) asm("nuc_rd-def-rmacro");
bool nuc_rd_fn_type_form_QMARK(struct nuc_Node* /* nullable */ form) asm("nuc_rd-fn-type-form_QMARK");
struct nuc_ReadResult nuc_rd_fuse_fn_params(struct nuc_Reader* self, struct nuc_Node* /* nullable */ paren_form, int32_t line) asm("nuc_rd-fuse-fn-params");
bool nuc_rd_open_segment_QMARK(struct nuc_StrView sv) asm("nuc_rd-open-segment_QMARK");
struct nuc_ReadResult nuc_rd_fuse_colon_paren(struct nuc_Reader* self, struct nuc_Node* /* nullable */ child, int32_t line) asm("nuc_rd-fuse-colon-paren");
struct nuc_ReadResult nuc_rd_skip_discard(struct nuc_Reader* self) asm("nuc_rd-skip-discard");
struct nuc_ReadResult nuc_rd_list(struct nuc_Reader* self, int32_t open_line) asm("nuc_rd-list");
struct nuc_ReadResult nuc_rd_lit_elems(struct nuc_Reader* self, struct nuc_StrView what, int32_t closer, int32_t open_line) asm("nuc_rd-lit-elems");
struct nuc_Node* nuc_rd_lit_cell(struct nuc_StrView name, struct nuc_Node* /* nullable */ elems, int32_t line, int32_t mark) asm("nuc_rd-lit-cell");
struct nuc_ReadResult nuc_rd_tagged(struct nuc_Reader* self, int32_t line) asm("nuc_rd-tagged");
bool nuc_rd_letter_QMARK(int32_t c) asm("nuc_rd-letter_QMARK");
struct nuc_ReadResult nuc_rd_atom_form(struct nuc_Reader* self, int32_t line) asm("nuc_rd-atom-form");
struct nuc_ReadResult nuc_rd_form(struct nuc_Reader* self) asm("nuc_rd-form");
bool nuc_reader_eof_QMARK(struct nuc_Reader* self) asm("nuc_reader-eof_QMARK");
struct nuc_ReadResult nuc_read_one(struct nuc_Reader* self) asm("nuc_read-one");
struct nuc_ReadResult nuc_read_all_with_macros(struct nuc_StrView src, struct nuc_Vector_nuc_RMacro* table) asm("nuc_read-all-with-macros");
struct nuc_ReadResult nuc_read_all(struct nuc_StrView src) asm("nuc_read-all");
struct nuc_ReadResult nuc_read_all_edn(struct nuc_StrView src) asm("nuc_read-all-edn");
void nuc_rd_write_escaped(struct nuc_String* out, struct nuc_StrView sv) asm("nuc_rd-write-escaped");
void nuc_rd_write_hex(struct nuc_String* out, uint64_t v) asm("nuc_rd-write-hex");
void nuc_sexp_write_string(struct nuc_String* out, struct nuc_StrView sv) asm("nuc_sexp-write-string");
void nuc_node_write(struct nuc_String* out, struct nuc_Node* /* nullable */ n) asm("nuc_node-write");
struct nuc_String nuc_node_str(struct nuc_Node* /* nullable */ n) asm("nuc_node-str");
bool nuc_node_eq(struct nuc_Node* /* nullable */ a, struct nuc_Node* /* nullable */ b) asm("nuc_node-eq");
