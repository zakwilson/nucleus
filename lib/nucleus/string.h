#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "allocator.h"
#include "core.h"
#include "strview.h"

/* Generated from lib/nucleus/string.nuc by nucleusc --emit-cheader */

#ifndef NUC_INST_nuc_Vector_u8
#define NUC_INST_nuc_Vector_u8
typedef struct nuc_Vector_u8 {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_AllocHandle alloc;
} nuc_Vector_u8;
#endif

typedef struct nuc_String {
    struct nuc_Vector_u8 bytes;
} nuc_String;

struct nuc_StrView nuc_string_as_view(struct nuc_String* self) asm("nuc_string-as-view");
struct nuc_String nuc_string_new(void) asm("nuc_string-new");
struct nuc_String nuc_string_new_alloc(struct nuc_AllocHandle* a) asm("nuc_string-new-alloc");
struct nuc_String nuc_string_with_capacity(size_t n) asm("nuc_string-with-capacity");
void nuc_string_push_bytes_raw(struct nuc_String* self, uint8_t* p, size_t n) asm("nuc_string-push-bytes-raw");
void nuc_string_push_char(struct nuc_String* self, uint32_t c) asm("nuc_string-push-char");
void nuc_string_push_str_unchecked(struct nuc_String* self, struct nuc_StrView* s) asm("nuc_string-push-str-unchecked");
/* string-push-str: uses an error-union or option type; not exported */
/* string-pop-char: uses an error-union or option type; not exported */
void nuc_string_clear(struct nuc_String* self) asm("nuc_string-clear");
/* string-truncate: uses an error-union or option type; not exported */
void nuc_string_truncate_unchecked(struct nuc_String* self, size_t byte_len) asm("nuc_string-truncate-unchecked");
void nuc_string_reserve(struct nuc_String* self, size_t extra) asm("nuc_string-reserve");
const char* nuc_string_as_cstr(struct nuc_String* self) asm("nuc_string-as-cstr");
void nuc_string_shrink_to_fit(struct nuc_String* self) asm("nuc_string-shrink-to-fit");
/* string-from-view: uses an error-union or option type; not exported */
struct nuc_String nuc_string_from_cstr_unchecked(const char* cs) asm("nuc_string-from-cstr-unchecked");
/* string-from-cstr: uses an error-union or option type; not exported */
void nuc_drop_pnuc_String(struct nuc_String* self) asm("nuc_drop.pnuc_String");
size_t nuc_byte_len_pnuc_String(struct nuc_String* self) asm("nuc_byte_len.pnuc_String");
/* byte-at: uses an error-union or option type; not exported */
struct nuc_ByteIter nuc_bytes_pnuc_String(struct nuc_String* self) asm("nuc_bytes.pnuc_String");
struct nuc_StrView nuc_as_view_pnuc_String(struct nuc_String* self) asm("nuc_as_view.pnuc_String");
/* sub-bytes: uses an error-union or option type; not exported */
/* byte-find: uses an error-union or option type; not exported */
size_t nuc_char_count_pnuc_String(struct nuc_String* self) asm("nuc_char_count.pnuc_String");
bool nuc_str_empty_QMARK_pnuc_String(struct nuc_String* self) asm("nuc_str_empty_QMARK.pnuc_String");
/* char-at: uses an error-union or option type; not exported */
struct nuc_CharIter nuc_chars_pnuc_String(struct nuc_String* self) asm("nuc_chars.pnuc_String");
bool nuc_starts_with_QMARK_pnuc_String_pnuc_StrView(struct nuc_String* self, struct nuc_StrView* prefix) asm("nuc_starts_with_QMARK.pnuc_String.pnuc_StrView");
bool nuc_ends_with_QMARK_pnuc_String_pnuc_StrView(struct nuc_String* self, struct nuc_StrView* suffix) asm("nuc_ends_with_QMARK.pnuc_String.pnuc_StrView");
bool nuc_contains_str_QMARK_pnuc_String_pnuc_StrView(struct nuc_String* self, struct nuc_StrView* needle) asm("nuc_contains_str_QMARK.pnuc_String.pnuc_StrView");
bool nuc_eq_nuc_String_nuc_String(struct nuc_String a, struct nuc_String b) asm("nuc_eq.nuc_String.nuc_String");
bool nuc_ne_nuc_String_nuc_String(struct nuc_String a, struct nuc_String b) asm("nuc_ne.nuc_String.nuc_String");
bool nuc_lt_nuc_String_nuc_String(struct nuc_String a, struct nuc_String b) asm("nuc_lt.nuc_String.nuc_String");
bool nuc_le_nuc_String_nuc_String(struct nuc_String a, struct nuc_String b) asm("nuc_le.nuc_String.nuc_String");
bool nuc_gt_nuc_String_nuc_String(struct nuc_String a, struct nuc_String b) asm("nuc_gt.nuc_String.nuc_String");
bool nuc_ge_nuc_String_nuc_String(struct nuc_String a, struct nuc_String b) asm("nuc_ge.nuc_String.nuc_String");
size_t nuc_hash_pnuc_String(struct nuc_String* self) asm("nuc_hash.pnuc_String");
