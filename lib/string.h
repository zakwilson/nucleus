#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"
#include "strview.h"

/* Generated from lib/string.nuc by nucleusc --emit-cheader */

typedef struct String {
    void* bytes;
} String;

struct StrView string_as_view(void* self) asm("string-as-view");
struct String string_new(void) asm("string-new");
struct String string_new_alloc(void* a) asm("string-new-alloc");
struct String string_with_capacity(size_t n) asm("string-with-capacity");
void string_push_bytes_raw(void* self, uint8_t* p, size_t n) asm("string-push-bytes-raw");
void string_push_char(void* self, uint32_t c) asm("string-push-char");
struct _BANGi32 string_push_str(void* self, void* s) asm("string-push-str");
/* string-pop-char: uses a defunion-template instance type; not exported */
void string_clear(void* self) asm("string-clear");
struct _BANGi32 string_truncate(void* self, size_t byte_len) asm("string-truncate");
void string_reserve(void* self, size_t extra) asm("string-reserve");
void string_shrink_to_fit(void* self) asm("string-shrink-to-fit");
struct _BANGString string_from_view(void* sv) asm("string-from-view");
struct String string_from_cstr_unchecked(const char* cs) asm("string-from-cstr-unchecked");
struct _BANGString string_from_cstr(const char* cs) asm("string-from-cstr");
void drop_pString(struct String* self) asm("drop.pString");
size_t byte_len_pString(void* self) asm("byte_len.pString");
struct _BANGui8 byte_at_pString_usize(void* self, size_t i) asm("byte_at.pString.usize");
struct ByteIter bytes_pString(void* self) asm("bytes.pString");
struct StrView as_view_pString(void* self) asm("as_view.pString");
void* sub_bytes_pString_usize_usize(void* self, size_t start, size_t end) asm("sub_bytes.pString.usize.usize");
/* byte-find: uses a defunion-template instance type; not exported */
size_t char_count_pString(void* self) asm("char_count.pString");
int32_t str_empty_QMARK_pString(void* self) asm("str_empty_QMARK.pString");
struct _BANGChar char_at_pString_usize(void* self, size_t i) asm("char_at.pString.usize");
struct CharIter chars_pString(void* self) asm("chars.pString");
int32_t starts_with_QMARK_pString_pStrView(void* self, void* prefix) asm("starts_with_QMARK.pString.pStrView");
int32_t ends_with_QMARK_pString_pStrView(void* self, void* suffix) asm("ends_with_QMARK.pString.pStrView");
int32_t contains_str_QMARK_pString_pStrView(void* self, void* needle) asm("contains_str_QMARK.pString.pStrView");
_Bool eq_String_String(struct String a, struct String b) asm("eq.String.String");
_Bool ne_String_String(struct String a, struct String b) asm("ne.String.String");
_Bool lt_String_String(struct String a, struct String b) asm("lt.String.String");
_Bool le_String_String(struct String a, struct String b) asm("le.String.String");
_Bool gt_String_String(struct String a, struct String b) asm("gt.String.String");
_Bool ge_String_String(struct String a, struct String b) asm("ge.String.String");
size_t hash_pString(void* self) asm("hash.pString");
