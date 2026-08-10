#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/char.nuc by nucleusc --emit-cheader */

typedef struct {
    struct Char ch;
    size_t nbytes;
    int32_t ok;
} DecodeResult;

size_t char-utf8-len(struct Char c);
size_t char-encode-utf8(struct Char c, uint8_t* buf);
struct DecodeResult decode-err(void);
struct DecodeResult char-decode-utf8(uint8_t* p, size_t len);
uint32_t char-to-u32(struct Char c);
struct _BANGChar char-from-u32(uint32_t n);
int32_t char-is-ascii(struct Char c);
int32_t char-is-digit(struct Char c);
int32_t char-is-alpha(struct Char c);
int32_t char-is-alnum(struct Char c);
int32_t char-is-whitespace(struct Char c);
struct Char char-ascii-upper(struct Char c);
struct Char char-ascii-lower(struct Char c);
