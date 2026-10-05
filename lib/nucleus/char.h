#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/nucleus/char.nuc by nucleusc --emit-cheader */

typedef struct nuc_DecodeResult {
    uint32_t ch;
    size_t nbytes;
    int32_t ok;
} nuc_DecodeResult;

size_t nuc_char_utf8_len(uint32_t c) asm("nuc_char-utf8-len");
size_t nuc_char_encode_utf8(uint32_t c, uint8_t* buf) asm("nuc_char-encode-utf8");
struct nuc_DecodeResult nuc_decode_err(void) asm("nuc_decode-err");
struct nuc_DecodeResult nuc_char_decode_utf8(uint8_t* p, size_t len) asm("nuc_char-decode-utf8");
uint32_t nuc_char_to_u32(uint32_t c) asm("nuc_char-to-u32");
/* char-from-u32: uses an error-union or option type; not exported */
bool nuc_char_is_ascii(uint32_t c) asm("nuc_char-is-ascii");
bool nuc_char_is_digit(uint32_t c) asm("nuc_char-is-digit");
bool nuc_char_is_alpha(uint32_t c) asm("nuc_char-is-alpha");
bool nuc_char_is_alnum(uint32_t c) asm("nuc_char-is-alnum");
bool nuc_char_is_whitespace(uint32_t c) asm("nuc_char-is-whitespace");
uint32_t nuc_char_ascii_upper(uint32_t c) asm("nuc_char-ascii-upper");
uint32_t nuc_char_ascii_lower(uint32_t c) asm("nuc_char-ascii-lower");
