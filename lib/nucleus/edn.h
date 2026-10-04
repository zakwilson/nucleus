#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"
#include "string.h"
#include "read.h"
#include "keyword.h"

/* Generated from lib/edn.nuc by nucleusc --emit-cheader */

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

int32_t edn__edn_kind(struct edn__Node* /* nullable */ n) asm("edn__edn-kind");
struct edn__StrView edn__edn_kind_name(int32_t k) asm("edn__edn-kind-name");
int32_t edn__edn_skip(struct edn__Node* /* nullable */ n) asm("edn__edn-skip");
size_t edn__edn_count(struct edn__Node* /* nullable */ n) asm("edn__edn-count");
struct edn__Node* /* nullable */ edn__edn_nth(struct edn__Node* /* nullable */ n, size_t i) asm("edn__edn-nth");
struct edn__Node* /* nullable */ edn__edn_elems(struct edn__Node* /* nullable */ n) asm("edn__edn-elems");
struct edn__Node* /* nullable */ edn__edn_key(struct edn__Node* /* nullable */ m, size_t i) asm("edn__edn-key");
struct edn__Node* /* nullable */ edn__edn_val(struct edn__Node* /* nullable */ m, size_t i) asm("edn__edn-val");
bool edn__edn_eq(struct edn__Node* /* nullable */ a, struct edn__Node* /* nullable */ b) asm("edn__edn-eq");
struct edn__Node* /* nullable */ edn__edn_lookup(struct edn__Node* /* nullable */ m, struct edn__Node* /* nullable */ key) asm("edn__edn-lookup");
struct edn__Node* /* nullable */ edn__edn_get(struct edn__Node* /* nullable */ m, struct edn__StrView name) asm("edn__edn-get");
/* edn-tag: uses an error-union or option type; not exported */
struct edn__Node* /* nullable */ edn__edn_tagged_value(struct edn__Node* /* nullable */ n) asm("edn__edn-tagged-value");
/* edn-bool: uses an error-union or option type; not exported */
/* edn-int: uses an error-union or option type; not exported */
/* edn-float: uses an error-union or option type; not exported */
/* edn-str: uses an error-union or option type; not exported */
/* edn-char: uses an error-union or option type; not exported */
/* edn-symbol: uses an error-union or option type; not exported */
/* edn-keyword: uses an error-union or option type; not exported */
struct edn__ReadResult edn__edn_err(int32_t code, int32_t line, struct edn__String* msg) asm("edn__edn-err");
bool edn__edn_sym_byte_QMARK(int32_t c) asm("edn__edn-sym-byte_QMARK");
bool edn__edn_sym_part_QMARK(struct edn__StrView sv) asm("edn__edn-sym-part_QMARK");
bool edn__edn_symbol_ok_QMARK(struct edn__StrView sv) asm("edn__edn-symbol-ok_QMARK");
struct edn__ReadResult edn__edn_validate(struct edn__Node* /* nullable */ n, int32_t line) asm("edn__edn-validate");
struct edn__ReadResult edn__edn_parse(struct edn__StrView src) asm("edn__edn-parse");
struct edn__ReadResult edn__edn_parse_all(struct edn__StrView src) asm("edn__edn-parse-all");
void edn__edn_write_hex4(struct edn__String* out, int32_t cp) asm("edn__edn-write-hex4");
void edn__edn_write_string(struct edn__String* out, struct edn__StrView sv) asm("edn__edn-write-string");
void edn__edn_write_char(struct edn__String* out, int32_t cp) asm("edn__edn-write-char");
void edn__edn_write_elems(struct edn__String* out, struct edn__Node* n, int32_t start) asm("edn__edn-write-elems");
void edn__edn_write_pString_pNode(struct edn__String* out, struct edn__Node* /* nullable */ n) asm("edn__edn_write.pString.pNode");
struct edn__String edn__edn_text(struct edn__Node* /* nullable */ n) asm("edn__edn-text");
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
bool edn__edn_float_text_ok_QMARK(struct edn__String* out, size_t from) asm("edn__edn-float-text-ok_QMARK");
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
struct edn__ReadResult edn__edn_expected(struct edn__StrView what, struct edn__Node* /* nullable */ n) asm("edn__edn-expected");
struct edn__ReadResult edn__edn_out_of_range(struct edn__Node* /* nullable */ n, struct edn__StrView what) asm("edn__edn-out-of-range");
struct edn__ReadResult edn__edn_int_in(struct edn__Node* /* nullable */ n, int64_t lo, int64_t hi, struct edn__StrView what, int64_t* v) asm("edn__edn-int-in");
struct edn__ReadResult edn__edn_read_pi8_pNode(int8_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pi8.pNode");
struct edn__ReadResult edn__edn_read_pi16_pNode(int16_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pi16.pNode");
struct edn__ReadResult edn__edn_read_pi32_pNode(int32_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pi32.pNode");
struct edn__ReadResult edn__edn_read_pi64_pNode(int64_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pi64.pNode");
struct edn__ReadResult edn__edn_read_pu8_pNode(uint8_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pu8.pNode");
struct edn__ReadResult edn__edn_read_pu16_pNode(uint16_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pu16.pNode");
struct edn__ReadResult edn__edn_read_pu32_pNode(uint32_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pu32.pNode");
struct edn__ReadResult edn__edn_read_pu64_pNode(uint64_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pu64.pNode");
struct edn__ReadResult edn__edn_read_pf64_pNode(double* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pf64.pNode");
struct edn__ReadResult edn__edn_read_pf32_pNode(float* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pf32.pNode");
struct edn__ReadResult edn__edn_read_pbool_pNode(bool* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pbool.pNode");
struct edn__ReadResult edn__edn_read_pChar_pNode(uint32_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pChar.pNode");
struct edn__ReadResult edn__edn_read_pStrView_pNode(struct edn__StrView* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pStrView.pNode");
struct edn__ReadResult edn__edn_read_pString_pNode(struct edn__String* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pString.pNode");
struct edn__ReadResult edn__edn_read_pKeyword_pNode(struct edn__Keyword* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_read.pKeyword.pNode");
struct edn__ReadResult edn__edn_decode_pi8_pNode(int8_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pi8.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pi8(int8_t* v) asm("edn__edn_release.pi8");
struct edn__ReadResult edn__edn_decode_pi16_pNode(int16_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pi16.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pi16(int16_t* v) asm("edn__edn_release.pi16");
struct edn__ReadResult edn__edn_decode_pi32_pNode(int32_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pi32.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pi32(int32_t* v) asm("edn__edn_release.pi32");
struct edn__ReadResult edn__edn_decode_pi64_pNode(int64_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pi64.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pi64(int64_t* v) asm("edn__edn_release.pi64");
struct edn__ReadResult edn__edn_decode_pu8_pNode(uint8_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pu8.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pu8(uint8_t* v) asm("edn__edn_release.pu8");
struct edn__ReadResult edn__edn_decode_pu16_pNode(uint16_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pu16.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pu16(uint16_t* v) asm("edn__edn_release.pu16");
struct edn__ReadResult edn__edn_decode_pu32_pNode(uint32_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pu32.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pu32(uint32_t* v) asm("edn__edn_release.pu32");
struct edn__ReadResult edn__edn_decode_pu64_pNode(uint64_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pu64.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pu64(uint64_t* v) asm("edn__edn_release.pu64");
struct edn__ReadResult edn__edn_decode_pf32_pNode(float* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pf32.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pf32(float* v) asm("edn__edn_release.pf32");
struct edn__ReadResult edn__edn_decode_pf64_pNode(double* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pf64.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pf64(double* v) asm("edn__edn_release.pf64");
struct edn__ReadResult edn__edn_decode_pbool_pNode(bool* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pbool.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pbool(bool* v) asm("edn__edn_release.pbool");
struct edn__ReadResult edn__edn_decode_pChar_pNode(uint32_t* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pChar.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pChar(uint32_t* v) asm("edn__edn_release.pChar");
struct edn__ReadResult edn__edn_decode_pStrView_pNode(struct edn__StrView* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pStrView.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pStrView(struct edn__StrView* v) asm("edn__edn_release.pStrView");
struct edn__ReadResult edn__edn_decode_pKeyword_pNode(struct edn__Keyword* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pKeyword.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pKeyword(struct edn__Keyword* v) asm("edn__edn_release.pKeyword");
struct edn__ReadResult edn__edn_decode_pString_pNode(struct edn__String* dst, struct edn__Node* /* nullable */ n) asm("edn__edn_decode.pString.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn__edn_release_pString(struct edn__String* v) asm("edn__edn_release.pString");
bool edn__edn_failed_QMARK(struct edn__ReadResult* r) asm("edn__edn-failed_QMARK");
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
void edn__edn_put(struct edn__String* out, struct edn__StrView s) asm("edn__edn-put");
struct edn__ReadResult edn__edn_struct_map(struct edn__Node* /* nullable */ n, struct edn__StrView tag) asm("edn__edn-struct-map");
bool edn__edn_field_listed_QMARK(struct edn__StrView fields, struct edn__StrView name) asm("edn__edn-field-listed_QMARK");
struct edn__ReadResult edn__edn_struct_keys(struct edn__Node* /* nullable */ m, struct edn__StrView tag, struct edn__StrView fields) asm("edn__edn-struct-keys");
struct edn__ReadResult edn__edn_at_key(struct edn__ReadResult r, struct edn__StrView key) asm("edn__edn-at-key");
