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

int32_t edn_kind(struct Node* /* nullable */ n) asm("edn-kind");
struct StrView edn_kind_name(int32_t k) asm("edn-kind-name");
int32_t edn_skip(struct Node* /* nullable */ n) asm("edn-skip");
size_t edn_count(struct Node* /* nullable */ n) asm("edn-count");
struct Node* /* nullable */ edn_nth(struct Node* /* nullable */ n, size_t i) asm("edn-nth");
struct Node* /* nullable */ edn_elems(struct Node* /* nullable */ n) asm("edn-elems");
struct Node* /* nullable */ edn_key(struct Node* /* nullable */ m, size_t i) asm("edn-key");
struct Node* /* nullable */ edn_val(struct Node* /* nullable */ m, size_t i) asm("edn-val");
bool edn_eq(struct Node* /* nullable */ a, struct Node* /* nullable */ b) asm("edn-eq");
struct Node* /* nullable */ edn_lookup(struct Node* /* nullable */ m, struct Node* /* nullable */ key) asm("edn-lookup");
struct Node* /* nullable */ edn_get(struct Node* /* nullable */ m, struct StrView name) asm("edn-get");
/* edn-tag: uses an error-union or option type; not exported */
struct Node* /* nullable */ edn_tagged_value(struct Node* /* nullable */ n) asm("edn-tagged-value");
/* edn-bool: uses an error-union or option type; not exported */
/* edn-int: uses an error-union or option type; not exported */
/* edn-float: uses an error-union or option type; not exported */
/* edn-str: uses an error-union or option type; not exported */
/* edn-char: uses an error-union or option type; not exported */
/* edn-symbol: uses an error-union or option type; not exported */
/* edn-keyword: uses an error-union or option type; not exported */
struct ReadResult edn_err(int32_t code, int32_t line, struct String* msg) asm("edn-err");
bool edn_sym_byte_QMARK(int32_t c) asm("edn-sym-byte_QMARK");
bool edn_sym_part_QMARK(struct StrView sv) asm("edn-sym-part_QMARK");
bool edn_symbol_ok_QMARK(struct StrView sv) asm("edn-symbol-ok_QMARK");
struct ReadResult edn_validate(struct Node* /* nullable */ n, int32_t line) asm("edn-validate");
struct ReadResult edn_parse(struct StrView src) asm("edn-parse");
struct ReadResult edn_parse_all(struct StrView src) asm("edn-parse-all");
void edn_write_hex4(struct String* out, int32_t cp) asm("edn-write-hex4");
void edn_write_string(struct String* out, struct StrView sv) asm("edn-write-string");
void edn_write_char(struct String* out, int32_t cp) asm("edn-write-char");
void edn_write_elems(struct String* out, struct Node* n, int32_t start) asm("edn-write-elems");
void edn_write_pString_pNode(struct String* out, struct Node* /* nullable */ n) asm("edn_write.pString.pNode");
struct String edn_text(struct Node* /* nullable */ n) asm("edn-text");
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
bool edn_float_text_ok_QMARK(struct String* out, size_t from) asm("edn-float-text-ok_QMARK");
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
/* edn-write: uses an error-union or option type; not exported */
struct ReadResult edn_expected(struct StrView what, struct Node* /* nullable */ n) asm("edn-expected");
struct ReadResult edn_out_of_range(struct Node* /* nullable */ n, struct StrView what) asm("edn-out-of-range");
struct ReadResult edn_int_in(struct Node* /* nullable */ n, int64_t lo, int64_t hi, struct StrView what, int64_t* v) asm("edn-int-in");
struct ReadResult edn_read_pi8_pNode(int8_t* dst, struct Node* /* nullable */ n) asm("edn_read.pi8.pNode");
struct ReadResult edn_read_pi16_pNode(int16_t* dst, struct Node* /* nullable */ n) asm("edn_read.pi16.pNode");
struct ReadResult edn_read_pi32_pNode(int32_t* dst, struct Node* /* nullable */ n) asm("edn_read.pi32.pNode");
struct ReadResult edn_read_pi64_pNode(int64_t* dst, struct Node* /* nullable */ n) asm("edn_read.pi64.pNode");
struct ReadResult edn_read_pu8_pNode(uint8_t* dst, struct Node* /* nullable */ n) asm("edn_read.pu8.pNode");
struct ReadResult edn_read_pu16_pNode(uint16_t* dst, struct Node* /* nullable */ n) asm("edn_read.pu16.pNode");
struct ReadResult edn_read_pu32_pNode(uint32_t* dst, struct Node* /* nullable */ n) asm("edn_read.pu32.pNode");
struct ReadResult edn_read_pu64_pNode(uint64_t* dst, struct Node* /* nullable */ n) asm("edn_read.pu64.pNode");
struct ReadResult edn_read_pf64_pNode(double* dst, struct Node* /* nullable */ n) asm("edn_read.pf64.pNode");
struct ReadResult edn_read_pf32_pNode(float* dst, struct Node* /* nullable */ n) asm("edn_read.pf32.pNode");
struct ReadResult edn_read_pbool_pNode(bool* dst, struct Node* /* nullable */ n) asm("edn_read.pbool.pNode");
struct ReadResult edn_read_pChar_pNode(uint32_t* dst, struct Node* /* nullable */ n) asm("edn_read.pChar.pNode");
struct ReadResult edn_read_pStrView_pNode(struct StrView* dst, struct Node* /* nullable */ n) asm("edn_read.pStrView.pNode");
struct ReadResult edn_read_pString_pNode(struct String* dst, struct Node* /* nullable */ n) asm("edn_read.pString.pNode");
struct ReadResult edn_read_pKeyword_pNode(struct Keyword* dst, struct Node* /* nullable */ n) asm("edn_read.pKeyword.pNode");
struct ReadResult edn_decode_pi8_pNode(int8_t* dst, struct Node* /* nullable */ n) asm("edn_decode.pi8.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pi8(int8_t* v) asm("edn_release.pi8");
struct ReadResult edn_decode_pi16_pNode(int16_t* dst, struct Node* /* nullable */ n) asm("edn_decode.pi16.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pi16(int16_t* v) asm("edn_release.pi16");
struct ReadResult edn_decode_pi32_pNode(int32_t* dst, struct Node* /* nullable */ n) asm("edn_decode.pi32.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pi32(int32_t* v) asm("edn_release.pi32");
struct ReadResult edn_decode_pi64_pNode(int64_t* dst, struct Node* /* nullable */ n) asm("edn_decode.pi64.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pi64(int64_t* v) asm("edn_release.pi64");
struct ReadResult edn_decode_pu8_pNode(uint8_t* dst, struct Node* /* nullable */ n) asm("edn_decode.pu8.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pu8(uint8_t* v) asm("edn_release.pu8");
struct ReadResult edn_decode_pu16_pNode(uint16_t* dst, struct Node* /* nullable */ n) asm("edn_decode.pu16.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pu16(uint16_t* v) asm("edn_release.pu16");
struct ReadResult edn_decode_pu32_pNode(uint32_t* dst, struct Node* /* nullable */ n) asm("edn_decode.pu32.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pu32(uint32_t* v) asm("edn_release.pu32");
struct ReadResult edn_decode_pu64_pNode(uint64_t* dst, struct Node* /* nullable */ n) asm("edn_decode.pu64.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pu64(uint64_t* v) asm("edn_release.pu64");
struct ReadResult edn_decode_pf32_pNode(float* dst, struct Node* /* nullable */ n) asm("edn_decode.pf32.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pf32(float* v) asm("edn_release.pf32");
struct ReadResult edn_decode_pf64_pNode(double* dst, struct Node* /* nullable */ n) asm("edn_decode.pf64.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pf64(double* v) asm("edn_release.pf64");
struct ReadResult edn_decode_pbool_pNode(bool* dst, struct Node* /* nullable */ n) asm("edn_decode.pbool.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pbool(bool* v) asm("edn_release.pbool");
struct ReadResult edn_decode_pChar_pNode(uint32_t* dst, struct Node* /* nullable */ n) asm("edn_decode.pChar.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pChar(uint32_t* v) asm("edn_release.pChar");
struct ReadResult edn_decode_pStrView_pNode(struct StrView* dst, struct Node* /* nullable */ n) asm("edn_decode.pStrView.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pStrView(struct StrView* v) asm("edn_release.pStrView");
struct ReadResult edn_decode_pKeyword_pNode(struct Keyword* dst, struct Node* /* nullable */ n) asm("edn_decode.pKeyword.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pKeyword(struct Keyword* v) asm("edn_release.pKeyword");
struct ReadResult edn_decode_pString_pNode(struct String* dst, struct Node* /* nullable */ n) asm("edn_decode.pString.pNode");
/* edn-encode: uses an error-union or option type; not exported */
void edn_release_pString(struct String* v) asm("edn_release.pString");
bool edn_failed_QMARK(struct ReadResult* r) asm("edn-failed_QMARK");
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
void edn_put(struct String* out, struct StrView s) asm("edn-put");
struct ReadResult edn_struct_map(struct Node* /* nullable */ n, struct StrView tag) asm("edn-struct-map");
bool edn_field_listed_QMARK(struct StrView fields, struct StrView name) asm("edn-field-listed_QMARK");
struct ReadResult edn_struct_keys(struct Node* /* nullable */ m, struct StrView tag, struct StrView fields) asm("edn-struct-keys");
struct ReadResult edn_at_key(struct ReadResult r, struct StrView key) asm("edn-at-key");
