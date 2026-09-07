#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"
#include "strview.h"

/* Generated from lib/strview-str.nuc by nucleusc --emit-cheader */

size_t byte_len(struct StrView* self) asm("byte-len");
/* byte-at: uses an error-union or option type; not exported */
struct ByteIter bytes(struct StrView* self);
struct StrView as_view(struct StrView* self) asm("as-view");
/* sub-bytes: uses an error-union or option type; not exported */
/* byte-find: uses a defunion-template instance type; not exported */
size_t char_count(struct StrView* self) asm("char-count");
bool str_empty_QMARK(struct StrView* self) asm("str-empty_QMARK");
/* char-at: uses an error-union or option type; not exported */
struct CharIter chars(struct StrView* self);
bool starts_with_QMARK(struct StrView* self, struct StrView* prefix) asm("starts-with_QMARK");
bool ends_with_QMARK(struct StrView* self, struct StrView* suffix) asm("ends-with_QMARK");
bool contains_str_QMARK(struct StrView* self, struct StrView* needle) asm("contains-str_QMARK");
