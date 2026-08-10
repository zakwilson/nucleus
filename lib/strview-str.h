#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/strview-str.nuc by nucleusc --emit-cheader */

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
