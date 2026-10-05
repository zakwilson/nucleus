#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"

/* Generated from lib/nucleus/strview.nuc by nucleusc --emit-cheader */

bool nuc_strview_eq(struct nuc_StrView* a, struct nuc_StrView* b) asm("nuc_strview-eq");
typedef struct nuc_ByteIter {
    uint8_t* buf;
    size_t pos;
    size_t len;
} nuc_ByteIter;

/* next: uses an error-union or option type; not exported */
size_t nuc_strview_hash(struct nuc_StrView* sv) asm("nuc_strview-hash");
struct nuc_StrView nuc_strview(uint8_t* data, size_t len);
struct nuc_StrView nuc_strview_from_cstr(const char* cs) asm("nuc_strview-from-cstr");
const char* nuc_strview_to_cstr(struct nuc_StrView* sv) asm("nuc_strview-to-cstr");
bool nuc_eq_nuc_StrView_nuc_StrView(struct nuc_StrView a, struct nuc_StrView b) asm("nuc_eq.nuc_StrView.nuc_StrView");
bool nuc_ne_nuc_StrView_nuc_StrView(struct nuc_StrView a, struct nuc_StrView b) asm("nuc_ne.nuc_StrView.nuc_StrView");
typedef struct nuc_CharIter {
    uint8_t* buf;
    size_t pos;
    size_t len;
} nuc_CharIter;

/* next: uses an error-union or option type; not exported */
size_t nuc_strview_byte_len(struct nuc_StrView* sv) asm("nuc_strview-byte-len");
/* strview-byte-at: uses an error-union or option type; not exported */
struct nuc_ByteIter nuc_strview_bytes(struct nuc_StrView* sv) asm("nuc_strview-bytes");
struct nuc_StrView nuc_strview_as_view(struct nuc_StrView* sv) asm("nuc_strview-as-view");
struct nuc_ByteIter nuc_cstr_bytes(const char* cs) asm("nuc_cstr-bytes");
struct nuc_CharIter nuc_cstr_chars(const char* cs) asm("nuc_cstr-chars");
/* strview-sub-bytes: uses an error-union or option type; not exported */
/* strview-find: uses an error-union or option type; not exported */
/* strview-find-byte: uses an error-union or option type; not exported */
/* strview-rfind-byte: uses an error-union or option type; not exported */
/* strview-rfind: uses an error-union or option type; not exported */
/* strview-find-char: uses an error-union or option type; not exported */
/* strview-rfind-char: uses an error-union or option type; not exported */
size_t nuc_strview_char_count(struct nuc_StrView* sv) asm("nuc_strview-char-count");
/* strview-char-at: uses an error-union or option type; not exported */
struct nuc_CharIter nuc_strview_chars(struct nuc_StrView* sv) asm("nuc_strview-chars");
bool nuc_strview_empty(struct nuc_StrView* sv) asm("nuc_strview-empty");
bool nuc_strview_starts_with(struct nuc_StrView* sv, struct nuc_StrView* prefix) asm("nuc_strview-starts-with");
bool nuc_strview_ends_with(struct nuc_StrView* sv, struct nuc_StrView* suffix) asm("nuc_strview-ends-with");
/* strview-parse-magnitude: uses an error-union or option type; not exported */
int32_t nuc_strview_parse_sign(struct nuc_StrView sv, size_t* out_start) asm("nuc_strview-parse-sign");
struct nuc_StrView nuc_strview_drop_bytes(struct nuc_StrView sv, size_t start) asm("nuc_strview-drop-bytes");
struct nuc_StrView nuc_strview_take_bytes(struct nuc_StrView sv, size_t n) asm("nuc_strview-take-bytes");
bool nuc_strview_has_prefix(struct nuc_StrView sv, struct nuc_StrView prefix) asm("nuc_strview-has-prefix");
bool nuc_strview_has_suffix(struct nuc_StrView sv, struct nuc_StrView suffix) asm("nuc_strview-has-suffix");
bool nuc_strview_contains(struct nuc_StrView sv, struct nuc_StrView needle) asm("nuc_strview-contains");
bool nuc_strview_contains_str(struct nuc_StrView* sv, struct nuc_StrView* needle) asm("nuc_strview-contains-str");
bool nuc_strview_is_ascii_ws(uint8_t b) asm("nuc_strview-is-ascii-ws");
struct nuc_StrView nuc_strview_trim_start(struct nuc_StrView* sv) asm("nuc_strview-trim-start");
struct nuc_StrView nuc_strview_trim_end(struct nuc_StrView* sv) asm("nuc_strview-trim-end");
struct nuc_StrView nuc_strview_trim(struct nuc_StrView* sv) asm("nuc_strview-trim");
int32_t nuc_strview_cmp_raw(struct nuc_StrView* a, struct nuc_StrView* b) asm("nuc_strview-cmp-raw");
bool nuc_lt_nuc_StrView_nuc_StrView(struct nuc_StrView a, struct nuc_StrView b) asm("nuc_lt.nuc_StrView.nuc_StrView");
bool nuc_le_nuc_StrView_nuc_StrView(struct nuc_StrView a, struct nuc_StrView b) asm("nuc_le.nuc_StrView.nuc_StrView");
bool nuc_gt_nuc_StrView_nuc_StrView(struct nuc_StrView a, struct nuc_StrView b) asm("nuc_gt.nuc_StrView.nuc_StrView");
bool nuc_ge_nuc_StrView_nuc_StrView(struct nuc_StrView a, struct nuc_StrView b) asm("nuc_ge.nuc_StrView.nuc_StrView");
