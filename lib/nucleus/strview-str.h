#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"
#include "strview.h"

/* Generated from lib/nucleus/strview-str.nuc by nucleusc --emit-cheader */

size_t nuc_byte_len(struct nuc_StrView* self) asm("nuc_byte-len");
/* byte-at: uses an error-union or option type; not exported */
struct nuc_ByteIter nuc_bytes(struct nuc_StrView* self);
struct nuc_StrView nuc_as_view(struct nuc_StrView* self) asm("nuc_as-view");
/* sub-bytes: uses an error-union or option type; not exported */
/* byte-find: uses an error-union or option type; not exported */
size_t nuc_char_count(struct nuc_StrView* self) asm("nuc_char-count");
bool nuc_str_empty_QMARK(struct nuc_StrView* self) asm("nuc_str-empty_QMARK");
/* char-at: uses an error-union or option type; not exported */
struct nuc_CharIter nuc_chars(struct nuc_StrView* self);
bool nuc_starts_with_QMARK(struct nuc_StrView* self, struct nuc_StrView* prefix) asm("nuc_starts-with_QMARK");
bool nuc_ends_with_QMARK(struct nuc_StrView* self, struct nuc_StrView* suffix) asm("nuc_ends-with_QMARK");
bool nuc_contains_str_QMARK(struct nuc_StrView* self, struct nuc_StrView* needle) asm("nuc_contains-str_QMARK");
