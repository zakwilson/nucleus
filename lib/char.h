#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/char.nuc by nucleusc --emit-cheader */

typedef struct DecodeResult {
    uint32_t ch;
    size_t nbytes;
    int32_t ok;
} DecodeResult;

size_t char_utf8_len(uint32_t c) asm("char-utf8-len");
size_t char_encode_utf8(uint32_t c, uint8_t* buf) asm("char-encode-utf8");
struct DecodeResult decode_err(void) asm("decode-err");
struct DecodeResult char_decode_utf8(uint8_t* p, size_t len) asm("char-decode-utf8");
uint32_t char_to_u32(uint32_t c) asm("char-to-u32");
struct _BANGChar char_from_u32(uint32_t n) asm("char-from-u32");
int32_t char_is_ascii(uint32_t c) asm("char-is-ascii");
int32_t char_is_digit(uint32_t c) asm("char-is-digit");
int32_t char_is_alpha(uint32_t c) asm("char-is-alpha");
int32_t char_is_alnum(uint32_t c) asm("char-is-alnum");
int32_t char_is_whitespace(uint32_t c) asm("char-is-whitespace");
uint32_t char_ascii_upper(uint32_t c) asm("char-ascii-upper");
uint32_t char_ascii_lower(uint32_t c) asm("char-ascii-lower");
