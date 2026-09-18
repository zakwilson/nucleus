#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"
#include "allocator.h"
#include "strview.h"

/* Generated from lib/string.nuc by nucleusc --emit-cheader */

typedef struct String {
    void* bytes;
} String;

struct StrView string_as_view(struct String* self) asm("string-as-view");
struct String string_new(void) asm("string-new");
struct String string_new_alloc(struct AllocHandle* a) asm("string-new-alloc");
struct String string_with_capacity(size_t n) asm("string-with-capacity");
void string_push_bytes_raw(struct String* self, uint8_t* p, size_t n) asm("string-push-bytes-raw");
void string_push_char(struct String* self, uint32_t c) asm("string-push-char");
void string_push_str_unchecked(struct String* self, struct StrView* s) asm("string-push-str-unchecked");
/* string-push-str: uses an error-union or option type; not exported */
/* string-pop-char: uses an error-union or option type; not exported */
void string_clear(struct String* self) asm("string-clear");
/* string-truncate: uses an error-union or option type; not exported */
void string_truncate_unchecked(struct String* self, size_t byte_len) asm("string-truncate-unchecked");
void string_reserve(struct String* self, size_t extra) asm("string-reserve");
const char* string_as_cstr(struct String* self) asm("string-as-cstr");
void string_shrink_to_fit(struct String* self) asm("string-shrink-to-fit");
/* string-from-view: uses an error-union or option type; not exported */
struct String string_from_cstr_unchecked(const char* cs) asm("string-from-cstr-unchecked");
/* string-from-cstr: uses an error-union or option type; not exported */
void drop_pString(struct String* self) asm("drop.pString");
size_t byte_len_pString(struct String* self) asm("byte_len.pString");
/* byte-at: uses an error-union or option type; not exported */
struct ByteIter bytes_pString(struct String* self) asm("bytes.pString");
struct StrView as_view_pString(struct String* self) asm("as_view.pString");
/* sub-bytes: uses an error-union or option type; not exported */
/* byte-find: uses an error-union or option type; not exported */
size_t char_count_pString(struct String* self) asm("char_count.pString");
bool str_empty_QMARK_pString(struct String* self) asm("str_empty_QMARK.pString");
/* char-at: uses an error-union or option type; not exported */
struct CharIter chars_pString(struct String* self) asm("chars.pString");
bool starts_with_QMARK_pString_pStrView(struct String* self, struct StrView* prefix) asm("starts_with_QMARK.pString.pStrView");
bool ends_with_QMARK_pString_pStrView(struct String* self, struct StrView* suffix) asm("ends_with_QMARK.pString.pStrView");
bool contains_str_QMARK_pString_pStrView(struct String* self, struct StrView* needle) asm("contains_str_QMARK.pString.pStrView");
bool eq_String_String(struct String a, struct String b) asm("eq.String.String");
bool ne_String_String(struct String a, struct String b) asm("ne.String.String");
bool lt_String_String(struct String a, struct String b) asm("lt.String.String");
bool le_String_String(struct String a, struct String b) asm("le.String.String");
bool gt_String_String(struct String a, struct String b) asm("gt.String.String");
bool ge_String_String(struct String a, struct String b) asm("ge.String.String");
size_t hash_pString(struct String* self) asm("hash.pString");
