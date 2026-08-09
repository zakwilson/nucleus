#pragma once
#include <stdint.h>
#include <stdbool.h>

/* Generated from lib/strview-str.nuc by nucleusc --emit-cheader */

struct usize byte-len(void* self);
struct _BANGui8 byte-at(void* self, struct usize i);
struct ByteIter bytes(void* self);
struct StrView as-view(void* self);
void* sub-bytes(void* self, struct usize start, struct usize end);
void* byte-find(void* self, void* needle);
struct usize char-count(void* self);
int32_t str-empty_QMARK(void* self);
struct _BANGChar char-at(void* self, struct usize i);
struct CharIter chars(void* self);
int32_t starts-with_QMARK(void* self, void* prefix);
int32_t ends-with_QMARK(void* self, void* suffix);
int32_t contains-str_QMARK(void* self, void* needle);
