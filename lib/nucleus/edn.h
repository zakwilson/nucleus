#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"
#include "string.h"
#include "read.h"
#include "keyword.h"

/* Generated from lib/nucleus/edn.nuc by nucleusc --emit-cheader */

enum EdnKind {
    EdnKind_EDN_NIL = 0,
    EdnKind_EDN_BOOL = 1,
    EdnKind_EDN_INT = 2,
    EdnKind_EDN_FLOAT = 3,
    EdnKind_EDN_STR = 4,
    EdnKind_EDN_CHAR = 5,
    EdnKind_EDN_SYM = 6,
    EdnKind_EDN_KEYWORD = 7,
    EdnKind_EDN_LIST = 8,
    EdnKind_EDN_VECTOR = 9,
    EdnKind_EDN_MAP = 10,
    EdnKind_EDN_SET = 11,
    EdnKind_EDN_TAGGED = 12
};

int32_t nuc_edn_kind(struct nuc_Node* /* nullable */ n) asm("nuc_edn-kind");
struct nuc_StrView nuc_edn_kind_name(int32_t k) asm("nuc_edn-kind-name");
int32_t nuc_edn_skip(struct nuc_Node* /* nullable */ n) asm("nuc_edn-skip");
size_t nuc_edn_count(struct nuc_Node* /* nullable */ n) asm("nuc_edn-count");
struct nuc_Node* /* nullable */ nuc_edn_nth(struct nuc_Node* /* nullable */ n, size_t i) asm("nuc_edn-nth");
struct nuc_Node* /* nullable */ nuc_edn_elems(struct nuc_Node* /* nullable */ n) asm("nuc_edn-elems");
struct nuc_Node* /* nullable */ nuc_edn_key(struct nuc_Node* /* nullable */ m, size_t i) asm("nuc_edn-key");
struct nuc_Node* /* nullable */ nuc_edn_val(struct nuc_Node* /* nullable */ m, size_t i) asm("nuc_edn-val");
bool nuc_edn_eq(struct nuc_Node* /* nullable */ a, struct nuc_Node* /* nullable */ b) asm("nuc_edn-eq");
struct nuc_Node* /* nullable */ nuc_edn_lookup(struct nuc_Node* /* nullable */ m, struct nuc_Node* /* nullable */ key) asm("nuc_edn-lookup");
struct nuc_Node* /* nullable */ nuc_edn_get(struct nuc_Node* /* nullable */ m, struct nuc_StrView name) asm("nuc_edn-get");
/* edn-tag: uses an error-union or option type; not exported */
struct nuc_Node* /* nullable */ nuc_edn_tagged_value(struct nuc_Node* /* nullable */ n) asm("nuc_edn-tagged-value");
/* edn-bool: uses an error-union or option type; not exported */
/* edn-int: uses an error-union or option type; not exported */
/* edn-float: uses an error-union or option type; not exported */
/* edn-str: uses an error-union or option type; not exported */
/* edn-char: uses an error-union or option type; not exported */
/* edn-symbol: uses an error-union or option type; not exported */
/* edn-keyword: uses an error-union or option type; not exported */
struct nuc_ReadResult nuc_edn_err(int32_t code, int32_t line, struct nuc_String* msg) asm("nuc_edn-err");
bool nuc_edn_sym_byte_QMARK(int32_t c) asm("nuc_edn-sym-byte_QMARK");
bool nuc_edn_sym_part_QMARK(struct nuc_StrView sv) asm("nuc_edn-sym-part_QMARK");
bool nuc_edn_symbol_ok_QMARK(struct nuc_StrView sv) asm("nuc_edn-symbol-ok_QMARK");
struct nuc_ReadResult nuc_edn_validate(struct nuc_Node* /* nullable */ n, int32_t line) asm("nuc_edn-validate");
struct nuc_ReadResult nuc_edn_parse(struct nuc_StrView src) asm("nuc_edn-parse");
struct nuc_ReadResult nuc_edn_parse_all(struct nuc_StrView src) asm("nuc_edn-parse-all");
void nuc_edn_write_hex4(struct nuc_String* out, int32_t cp) asm("nuc_edn-write-hex4");
void nuc_edn_write_string(struct nuc_String* out, struct nuc_StrView sv) asm("nuc_edn-write-string");
void nuc_edn_write_char(struct nuc_String* out, int32_t cp) asm("nuc_edn-write-char");
void nuc_edn_write_elems(struct nuc_String* out, struct nuc_Node* n, int32_t start) asm("nuc_edn-write-elems");
void nuc_edn_write_pnuc_String_pnuc_Node(struct nuc_String* out, struct nuc_Node* /* nullable */ n) asm("nuc_edn_write.pnuc_String.pnuc_Node");
struct nuc_String nuc_edn_text(struct nuc_Node* /* nullable */ n) asm("nuc_edn-text");
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
bool nuc_edn_float_text_ok_QMARK(struct nuc_String* out, size_t from) asm("nuc_edn-float-text-ok_QMARK");
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
struct nuc_ReadResult nuc_edn_expected(struct nuc_StrView what, struct nuc_Node* /* nullable */ n) asm("nuc_edn-expected");
struct nuc_ReadResult nuc_edn_out_of_range(struct nuc_Node* /* nullable */ n, struct nuc_StrView what) asm("nuc_edn-out-of-range");
struct nuc_ReadResult nuc_edn_int_in(struct nuc_Node* /* nullable */ n, int64_t lo, int64_t hi, struct nuc_StrView what, int64_t* v) asm("nuc_edn-int-in");
struct nuc_ReadResult nuc_edn_read_pi8_pnuc_Node(int8_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pi8.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pi16_pnuc_Node(int16_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pi16.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pi32_pnuc_Node(int32_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pi32.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pi64_pnuc_Node(int64_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pi64.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pu8_pnuc_Node(uint8_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pu8.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pu16_pnuc_Node(uint16_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pu16.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pu32_pnuc_Node(uint32_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pu32.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pu64_pnuc_Node(uint64_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pu64.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pf64_pnuc_Node(double* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pf64.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pf32_pnuc_Node(float* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pf32.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pbool_pnuc_Node(bool* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pbool.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pChar_pnuc_Node(uint32_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pChar.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pnuc_StrView_pnuc_Node(struct nuc_StrView* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pnuc_StrView.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pnuc_String_pnuc_Node(struct nuc_String* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pnuc_String.pnuc_Node");
struct nuc_ReadResult nuc_edn_read_pnuc_Keyword_pnuc_Node(struct nuc_Keyword* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_read.pnuc_Keyword.pnuc_Node");
struct nuc_ReadResult nuc_edn_decode_pi8_pnuc_Node(int8_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pi8.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pi8(int8_t* v) asm("nuc_edn_release.pi8");
struct nuc_ReadResult nuc_edn_decode_pi16_pnuc_Node(int16_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pi16.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pi16(int16_t* v) asm("nuc_edn_release.pi16");
struct nuc_ReadResult nuc_edn_decode_pi32_pnuc_Node(int32_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pi32.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pi32(int32_t* v) asm("nuc_edn_release.pi32");
struct nuc_ReadResult nuc_edn_decode_pi64_pnuc_Node(int64_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pi64.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pi64(int64_t* v) asm("nuc_edn_release.pi64");
struct nuc_ReadResult nuc_edn_decode_pu8_pnuc_Node(uint8_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pu8.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pu8(uint8_t* v) asm("nuc_edn_release.pu8");
struct nuc_ReadResult nuc_edn_decode_pu16_pnuc_Node(uint16_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pu16.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pu16(uint16_t* v) asm("nuc_edn_release.pu16");
struct nuc_ReadResult nuc_edn_decode_pu32_pnuc_Node(uint32_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pu32.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pu32(uint32_t* v) asm("nuc_edn_release.pu32");
struct nuc_ReadResult nuc_edn_decode_pu64_pnuc_Node(uint64_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pu64.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pu64(uint64_t* v) asm("nuc_edn_release.pu64");
struct nuc_ReadResult nuc_edn_decode_pf32_pnuc_Node(float* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pf32.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pf32(float* v) asm("nuc_edn_release.pf32");
struct nuc_ReadResult nuc_edn_decode_pf64_pnuc_Node(double* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pf64.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pf64(double* v) asm("nuc_edn_release.pf64");
struct nuc_ReadResult nuc_edn_decode_pbool_pnuc_Node(bool* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pbool.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pbool(bool* v) asm("nuc_edn_release.pbool");
struct nuc_ReadResult nuc_edn_decode_pChar_pnuc_Node(uint32_t* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pChar.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pChar(uint32_t* v) asm("nuc_edn_release.pChar");
struct nuc_ReadResult nuc_edn_decode_pnuc_StrView_pnuc_Node(struct nuc_StrView* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pnuc_StrView.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pnuc_StrView(struct nuc_StrView* v) asm("nuc_edn_release.pnuc_StrView");
struct nuc_ReadResult nuc_edn_decode_pnuc_Keyword_pnuc_Node(struct nuc_Keyword* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pnuc_Keyword.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pnuc_Keyword(struct nuc_Keyword* v) asm("nuc_edn_release.pnuc_Keyword");
struct nuc_ReadResult nuc_edn_decode_pnuc_String_pnuc_Node(struct nuc_String* dst, struct nuc_Node* /* nullable */ n) asm("nuc_edn_decode.pnuc_String.pnuc_Node");
/* edn-encode: uses an error-union or option type; not exported */
void nuc_edn_release_pnuc_String(struct nuc_String* v) asm("nuc_edn_release.pnuc_String");
bool nuc_edn_failed_QMARK(struct nuc_ReadResult* r) asm("nuc_edn-failed_QMARK");
/* edn-read: generic template; not exported */
/* edn-write: generic template; not exported */
/* edn-decode: generic template; not exported */
/* edn-encode: generic template; not exported */
/* edn-release: generic template; not exported */
/* edn-decode: generic template; not exported */
/* edn-encode: generic template; not exported */
/* edn-release: generic template; not exported */
/* edn-decode: generic template; not exported */
/* edn-encode: generic template; not exported */
/* edn-release: generic template; not exported */
void nuc_edn_put(struct nuc_String* out, struct nuc_StrView s) asm("nuc_edn-put");
struct nuc_ReadResult nuc_edn_struct_map(struct nuc_Node* /* nullable */ n, struct nuc_StrView tag) asm("nuc_edn-struct-map");
bool nuc_edn_field_listed_QMARK(struct nuc_StrView fields, struct nuc_StrView name) asm("nuc_edn-field-listed_QMARK");
struct nuc_ReadResult nuc_edn_struct_keys(struct nuc_Node* /* nullable */ m, struct nuc_StrView tag, struct nuc_StrView fields) asm("nuc_edn-struct-keys");
struct nuc_ReadResult nuc_edn_at_key(struct nuc_ReadResult r, struct nuc_StrView key) asm("nuc_edn-at-key");
