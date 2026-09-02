#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"

/* Generated from lib/strview.nuc by nucleusc --emit-cheader */

bool strview_eq(void* a, void* b) asm("strview-eq");
typedef struct ByteIter {
    uint8_t* buf;
    size_t pos;
    size_t len;
} ByteIter;

/* next: uses a defunion-template instance type; not exported */
size_t strview_hash(void* sv) asm("strview-hash");
struct StrView strview(uint8_t* data, size_t len);
struct StrView strview_from_cstr(const char* cs) asm("strview-from-cstr");
const char* strview_to_cstr(void* sv) asm("strview-to-cstr");
size_t hash_pStrView(void* self) asm("hash.pStrView");
bool eq_StrView_StrView(struct StrView a, struct StrView b) asm("eq.StrView.StrView");
bool ne_StrView_StrView(struct StrView a, struct StrView b) asm("ne.StrView.StrView");
typedef struct CharIter {
    uint8_t* buf;
    size_t pos;
    size_t len;
} CharIter;

/* next: uses a defunion-template instance type; not exported */
size_t strview_byte_len(void* sv) asm("strview-byte-len");
/* strview-byte-at: uses an error-union or option type; not exported */
struct ByteIter strview_bytes(void* sv) asm("strview-bytes");
struct StrView strview_as_view(void* sv) asm("strview-as-view");
struct ByteIter cstr_bytes(const char* cs) asm("cstr-bytes");
struct CharIter cstr_chars(const char* cs) asm("cstr-chars");
/* strview-sub-bytes: uses an error-union or option type; not exported */
/* strview-find: uses a defunion-template instance type; not exported */
/* strview-find-byte: uses a defunion-template instance type; not exported */
/* strview-rfind-byte: uses a defunion-template instance type; not exported */
/* strview-rfind: uses a defunion-template instance type; not exported */
/* strview-find-char: uses a defunion-template instance type; not exported */
/* strview-rfind-char: uses a defunion-template instance type; not exported */
size_t strview_char_count(void* sv) asm("strview-char-count");
/* strview-char-at: uses an error-union or option type; not exported */
struct CharIter strview_chars(void* sv) asm("strview-chars");
bool strview_empty(void* sv) asm("strview-empty");
bool strview_starts_with(void* sv, void* prefix) asm("strview-starts-with");
bool strview_ends_with(void* sv, void* suffix) asm("strview-ends-with");
/* strview-parse-magnitude: uses an error-union or option type; not exported */
int32_t strview_parse_sign(struct StrView sv, size_t* out_start) asm("strview-parse-sign");
struct StrView strview_drop_bytes(struct StrView sv, size_t start) asm("strview-drop-bytes");
bool strview_has_prefix(struct StrView sv, struct StrView prefix) asm("strview-has-prefix");
bool strview_has_suffix(struct StrView sv, struct StrView suffix) asm("strview-has-suffix");
bool strview_contains_str(void* sv, void* needle) asm("strview-contains-str");
bool strview_is_ascii_ws(uint8_t b) asm("strview-is-ascii-ws");
struct StrView strview_trim_start(void* sv) asm("strview-trim-start");
struct StrView strview_trim_end(void* sv) asm("strview-trim-end");
struct StrView strview_trim(void* sv) asm("strview-trim");
int32_t strview_cmp_raw(void* a, void* b) asm("strview-cmp-raw");
bool lt_StrView_StrView(struct StrView a, struct StrView b) asm("lt.StrView.StrView");
bool le_StrView_StrView(struct StrView a, struct StrView b) asm("le.StrView.StrView");
bool gt_StrView_StrView(struct StrView a, struct StrView b) asm("gt.StrView.StrView");
bool ge_StrView_StrView(struct StrView a, struct StrView b) asm("ge.StrView.StrView");
