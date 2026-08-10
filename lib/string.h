#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/string.nuc by nucleusc --emit-cheader */

typedef struct {
    void* bytes;
} String;

struct StrView string-as-view(void* self);
struct String string-new(void);
struct String string-new-alloc(void* a);
struct String string-with-capacity(size_t n);
void string-push-bytes-raw(void* self, uint8_t* p, size_t n);
void string-push-char(void* self, struct Char c);
struct _BANGi32 string-push-str(void* self, void* s);
void* string-pop-char(void* self);
void string-clear(void* self);
struct _BANGi32 string-truncate(void* self, size_t byte-len);
void string-reserve(void* self, size_t extra);
void string-shrink-to-fit(void* self);
struct _BANGString string-from-view(void* sv);
struct String string-from-cstr-unchecked(const char* cs);
struct _BANGString string-from-cstr(const char* cs);
void drop(struct String* self);
size_t byte-len(void* self);
struct _BANGui8 byte-at(void* self, size_t i);
struct ByteIter bytes(void* self);
struct StrView as-view(void* self);
void* sub-bytes(void* self, size_t start, size_t end);
void* byte-find(void* self, void* needle);
size_t char-count(void* self);
int32_t str-empty_QMARK(void* self);
struct _BANGChar char-at(void* self, size_t i);
struct CharIter chars(void* self);
int32_t starts-with_QMARK(void* self, void* prefix);
int32_t ends-with_QMARK(void* self, void* suffix);
int32_t contains-str_QMARK(void* self, void* needle);
_Bool =(struct String a, struct String b);
_Bool _BANG=(struct String a, struct String b);
_Bool <(struct String a, struct String b);
_Bool <=(struct String a, struct String b);
_Bool >(struct String a, struct String b);
_Bool >=(struct String a, struct String b);
size_t hash(void* self);
