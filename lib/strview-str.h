#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "strview.h"
#include "prelude.h"

/* Generated from lib/strview-str.nuc by nucleusc --emit-cheader */

size_t byte_len(void* self) asm("byte-len");
/* byte-at: uses an error-union or option type; not exported */
struct ByteIter bytes(void* self);
struct StrView as_view(void* self) asm("as-view");
/* sub-bytes: uses an error-union or option type; not exported */
/* byte-find: uses a defunion-template instance type; not exported */
size_t char_count(void* self) asm("char-count");
bool str_empty_QMARK(void* self) asm("str-empty_QMARK");
/* char-at: uses an error-union or option type; not exported */
struct CharIter chars(void* self);
bool starts_with_QMARK(void* self, void* prefix) asm("starts-with_QMARK");
bool ends_with_QMARK(void* self, void* suffix) asm("ends-with_QMARK");
bool contains_str_QMARK(void* self, void* needle) asm("contains-str_QMARK");
