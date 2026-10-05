#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"
#include "strview.h"

/* Generated from lib/nucleus/intern-str.nuc by nucleusc --emit-cheader */

size_t nuc_hash_pnuc_Symbol(struct nuc_Symbol* self) asm("nuc_hash.pnuc_Symbol");
/* to-str: uses an error-union or option type; not exported */
size_t nuc_byte_len_pnuc_Symbol(struct nuc_Symbol* self) asm("nuc_byte_len.pnuc_Symbol");
/* byte-at: uses an error-union or option type; not exported */
struct nuc_ByteIter nuc_bytes_pnuc_Symbol(struct nuc_Symbol* self) asm("nuc_bytes.pnuc_Symbol");
struct nuc_StrView nuc_as_view_pnuc_Symbol(struct nuc_Symbol* self) asm("nuc_as_view.pnuc_Symbol");
/* sub-bytes: uses an error-union or option type; not exported */
/* byte-find: uses an error-union or option type; not exported */
size_t nuc_char_count_pnuc_Symbol(struct nuc_Symbol* self) asm("nuc_char_count.pnuc_Symbol");
bool nuc_str_empty_QMARK_pnuc_Symbol(struct nuc_Symbol* self) asm("nuc_str_empty_QMARK.pnuc_Symbol");
/* char-at: uses an error-union or option type; not exported */
struct nuc_CharIter nuc_chars_pnuc_Symbol(struct nuc_Symbol* self) asm("nuc_chars.pnuc_Symbol");
bool nuc_starts_with_QMARK_pnuc_Symbol_pnuc_StrView(struct nuc_Symbol* self, struct nuc_StrView* prefix) asm("nuc_starts_with_QMARK.pnuc_Symbol.pnuc_StrView");
bool nuc_ends_with_QMARK_pnuc_Symbol_pnuc_StrView(struct nuc_Symbol* self, struct nuc_StrView* suffix) asm("nuc_ends_with_QMARK.pnuc_Symbol.pnuc_StrView");
bool nuc_contains_str_QMARK_pnuc_Symbol_pnuc_StrView(struct nuc_Symbol* self, struct nuc_StrView* needle) asm("nuc_contains_str_QMARK.pnuc_Symbol.pnuc_StrView");
