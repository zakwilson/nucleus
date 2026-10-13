#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"
#include "strview.h"

/* Generated from lib/nucleus/strview-str.nuc by nucleusc --emit-cheader */

size_t nuc_byte_len_pnuc_StrView(struct nuc_StrView* self) asm("nuc_byte_len.pnuc_StrView");
/* byte-at: uses an error-union or option type; not exported */
struct nuc_ByteIter nuc_bytes_pnuc_StrView(struct nuc_StrView* self) asm("nuc_bytes.pnuc_StrView");
struct nuc_StrView nuc_as_view_pnuc_StrView(struct nuc_StrView* self) asm("nuc_as_view.pnuc_StrView");
/* sub-bytes: uses an error-union or option type; not exported */
/* byte-find: uses an error-union or option type; not exported */
size_t nuc_char_count_pnuc_StrView(struct nuc_StrView* self) asm("nuc_char_count.pnuc_StrView");
bool nuc_str_empty_QMARK_pnuc_StrView(struct nuc_StrView* self) asm("nuc_str_empty_QMARK.pnuc_StrView");
/* char-at: uses an error-union or option type; not exported */
struct nuc_CharIter nuc_chars_pnuc_StrView(struct nuc_StrView* self) asm("nuc_chars.pnuc_StrView");
bool nuc_starts_with_QMARK_pnuc_StrView_pnuc_StrView(struct nuc_StrView* self, struct nuc_StrView* prefix) asm("nuc_starts_with_QMARK.pnuc_StrView.pnuc_StrView");
bool nuc_ends_with_QMARK_pnuc_StrView_pnuc_StrView(struct nuc_StrView* self, struct nuc_StrView* suffix) asm("nuc_ends_with_QMARK.pnuc_StrView.pnuc_StrView");
bool nuc_contains_str_QMARK_pnuc_StrView_pnuc_StrView(struct nuc_StrView* self, struct nuc_StrView* needle) asm("nuc_contains_str_QMARK.pnuc_StrView.pnuc_StrView");
