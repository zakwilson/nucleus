#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/string.nuc by nucleusc --emit-cheader */

typedef struct {
    void* bytes;
} String;

struct StrView string_as_view(void* self) asm("string-as-view");
struct String string_new(void) asm("string-new");
struct String string_new_alloc(void* a) asm("string-new-alloc");
struct String string_with_capacity(size_t n) asm("string-with-capacity");
void string_push_bytes_raw(void* self, uint8_t* p, size_t n) asm("string-push-bytes-raw");
void string_push_char(void* self, struct Char c) asm("string-push-char");
struct _BANGi32 string_push_str(void* self, void* s) asm("string-push-str");
void* string_pop_char(void* self) asm("string-pop-char");
void string_clear(void* self) asm("string-clear");
struct _BANGi32 string_truncate(void* self, size_t byte_len) asm("string-truncate");
void string_reserve(void* self, size_t extra) asm("string-reserve");
void string_shrink_to_fit(void* self) asm("string-shrink-to-fit");
struct _BANGString string_from_view(void* sv) asm("string-from-view");
struct String string_from_cstr_unchecked(const char* cs) asm("string-from-cstr-unchecked");
struct _BANGString string_from_cstr(const char* cs) asm("string-from-cstr");
void drop(struct String* self);
size_t byte_len(void* self) asm("byte-len");
struct _BANGui8 byte_at(void* self, size_t i) asm("byte-at");
struct ByteIter bytes(void* self);
struct StrView as_view(void* self) asm("as-view");
void* sub_bytes(void* self, size_t start, size_t end) asm("sub-bytes");
void* byte_find(void* self, void* needle) asm("byte-find");
size_t char_count(void* self) asm("char-count");
int32_t str_empty_QMARK(void* self) asm("str-empty_QMARK");
struct _BANGChar char_at(void* self, size_t i) asm("char-at");
struct CharIter chars(void* self);
int32_t starts_with_QMARK(void* self, void* prefix) asm("starts-with_QMARK");
int32_t ends_with_QMARK(void* self, void* suffix) asm("ends-with_QMARK");
int32_t contains_str_QMARK(void* self, void* needle) asm("contains-str_QMARK");
_Bool _(struct String a, struct String b) asm("=");
_Bool _BANG_(struct String a, struct String b) asm("_BANG=");
_Bool _(struct String a, struct String b) asm("<");
_Bool __(struct String a, struct String b) asm("<=");
_Bool _(struct String a, struct String b) asm(">");
_Bool __(struct String a, struct String b) asm(">=");
size_t hash(void* self);
