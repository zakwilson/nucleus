#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/strview.nuc by nucleusc --emit-cheader */

size_t strview_len(void* sv) asm("strview-len");
int32_t strview_eq(void* a, void* b) asm("strview-eq");
typedef struct ByteIter {
    uint8_t* buf;
    size_t pos;
    size_t len;
} ByteIter;

void* next(void* self);
size_t strview_hash(void* sv) asm("strview-hash");
struct StrView* strview_from_cstr(const char* cs) asm("strview-from-cstr");
const char* strview_to_cstr(void* sv) asm("strview-to-cstr");
size_t hash(void* self);
_Bool _(struct StrView a, struct StrView b) asm("=");
_Bool _BANG_(struct StrView a, struct StrView b) asm("_BANG=");
typedef struct CharIter {
    uint8_t* buf;
    size_t pos;
    size_t len;
} CharIter;

void* next(void* self);
size_t strview_byte_len(void* sv) asm("strview-byte-len");
struct _BANGui8 strview_byte_at(void* sv, size_t i) asm("strview-byte-at");
struct ByteIter strview_bytes(void* sv) asm("strview-bytes");
struct StrView strview_as_view(void* sv) asm("strview-as-view");
struct ByteIter cstr_bytes(const char* cs) asm("cstr-bytes");
struct CharIter cstr_chars(const char* cs) asm("cstr-chars");
void* strview_sub_bytes(void* sv, size_t start, size_t end) asm("strview-sub-bytes");
void* strview_byte_find(void* sv, void* needle) asm("strview-byte-find");
size_t strview_char_count(void* sv) asm("strview-char-count");
struct _BANGChar strview_char_at(void* sv, size_t i) asm("strview-char-at");
struct CharIter strview_chars(void* sv) asm("strview-chars");
int32_t strview_empty(void* sv) asm("strview-empty");
int32_t strview_starts_with(void* sv, void* prefix) asm("strview-starts-with");
int32_t strview_ends_with(void* sv, void* suffix) asm("strview-ends-with");
int32_t strview_contains_str(void* sv, void* needle) asm("strview-contains-str");
int32_t strview_is_ascii_ws(uint8_t b) asm("strview-is-ascii-ws");
struct StrView strview_trim_start(void* sv) asm("strview-trim-start");
struct StrView strview_trim_end(void* sv) asm("strview-trim-end");
struct StrView strview_trim(void* sv) asm("strview-trim");
int32_t strview_cmp_raw(void* a, void* b) asm("strview-cmp-raw");
_Bool _(struct StrView a, struct StrView b) asm("<");
_Bool __(struct StrView a, struct StrView b) asm("<=");
_Bool _(struct StrView a, struct StrView b) asm(">");
_Bool __(struct StrView a, struct StrView b) asm(">=");
