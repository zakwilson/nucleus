#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/strview-str.nuc by nucleusc --emit-cheader */

size_t byte_len(void* self) asm("byte-len");
struct _BANGui8 byte_at(void* self, size_t i) asm("byte-at");
struct ByteIter bytes(void* self);
struct StrView as_view(void* self) asm("as-view");
void* sub_bytes(void* self, size_t start, size_t end) asm("sub-bytes");
/* byte-find: uses a defunion-template instance type; not exported */
size_t char_count(void* self) asm("char-count");
int32_t str_empty_QMARK(void* self) asm("str-empty_QMARK");
struct _BANGChar char_at(void* self, size_t i) asm("char-at");
struct CharIter chars(void* self);
int32_t starts_with_QMARK(void* self, void* prefix) asm("starts-with_QMARK");
int32_t ends_with_QMARK(void* self, void* suffix) asm("ends-with_QMARK");
int32_t contains_str_QMARK(void* self, void* needle) asm("contains-str_QMARK");
