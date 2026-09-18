#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"

/* Generated from lib/strview.nuc by nucleusc --emit-cheader */

bool strview_eq(struct StrView* a, struct StrView* b) asm("strview-eq");
typedef struct ByteIter {
    uint8_t* buf;
    size_t pos;
    size_t len;
} ByteIter;

/* next: uses an error-union or option type; not exported */
size_t strview_hash(struct StrView* sv) asm("strview-hash");
struct StrView strview(uint8_t* data, size_t len);
struct StrView strview_from_cstr(const char* cs) asm("strview-from-cstr");
const char* strview_to_cstr(struct StrView* sv) asm("strview-to-cstr");
bool eq_StrView_StrView(struct StrView a, struct StrView b) asm("eq.StrView.StrView");
bool ne_StrView_StrView(struct StrView a, struct StrView b) asm("ne.StrView.StrView");
typedef struct CharIter {
    uint8_t* buf;
    size_t pos;
    size_t len;
} CharIter;

/* next: uses an error-union or option type; not exported */
size_t strview_byte_len(struct StrView* sv) asm("strview-byte-len");
/* strview-byte-at: uses an error-union or option type; not exported */
struct ByteIter strview_bytes(struct StrView* sv) asm("strview-bytes");
struct StrView strview_as_view(struct StrView* sv) asm("strview-as-view");
struct ByteIter cstr_bytes(const char* cs) asm("cstr-bytes");
struct CharIter cstr_chars(const char* cs) asm("cstr-chars");
/* strview-sub-bytes: uses an error-union or option type; not exported */
/* strview-find: uses an error-union or option type; not exported */
/* strview-find-byte: uses an error-union or option type; not exported */
/* strview-rfind-byte: uses an error-union or option type; not exported */
/* strview-rfind: uses an error-union or option type; not exported */
/* strview-find-char: uses an error-union or option type; not exported */
/* strview-rfind-char: uses an error-union or option type; not exported */
size_t strview_char_count(struct StrView* sv) asm("strview-char-count");
/* strview-char-at: uses an error-union or option type; not exported */
struct CharIter strview_chars(struct StrView* sv) asm("strview-chars");
bool strview_empty(struct StrView* sv) asm("strview-empty");
bool strview_starts_with(struct StrView* sv, struct StrView* prefix) asm("strview-starts-with");
bool strview_ends_with(struct StrView* sv, struct StrView* suffix) asm("strview-ends-with");
/* strview-parse-magnitude: uses an error-union or option type; not exported */
int32_t strview_parse_sign(struct StrView sv, size_t* out_start) asm("strview-parse-sign");
struct StrView strview_drop_bytes(struct StrView sv, size_t start) asm("strview-drop-bytes");
struct StrView strview_take_bytes(struct StrView sv, size_t n) asm("strview-take-bytes");
bool strview_has_prefix(struct StrView sv, struct StrView prefix) asm("strview-has-prefix");
bool strview_has_suffix(struct StrView sv, struct StrView suffix) asm("strview-has-suffix");
bool strview_contains(struct StrView sv, struct StrView needle) asm("strview-contains");
bool strview_contains_str(struct StrView* sv, struct StrView* needle) asm("strview-contains-str");
bool strview_is_ascii_ws(uint8_t b) asm("strview-is-ascii-ws");
struct StrView strview_trim_start(struct StrView* sv) asm("strview-trim-start");
struct StrView strview_trim_end(struct StrView* sv) asm("strview-trim-end");
struct StrView strview_trim(struct StrView* sv) asm("strview-trim");
int32_t strview_cmp_raw(struct StrView* a, struct StrView* b) asm("strview-cmp-raw");
bool lt_StrView_StrView(struct StrView a, struct StrView b) asm("lt.StrView.StrView");
bool le_StrView_StrView(struct StrView a, struct StrView b) asm("le.StrView.StrView");
bool gt_StrView_StrView(struct StrView a, struct StrView b) asm("gt.StrView.StrView");
bool ge_StrView_StrView(struct StrView a, struct StrView b) asm("ge.StrView.StrView");
