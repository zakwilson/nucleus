#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "string.h"

/* Generated from lib/nucleus/io.nuc by nucleusc --emit-cheader */

typedef struct nuc_FdOut {
    int32_t fd;
} nuc_FdOut;

struct nuc_FdOut nuc_fd_out(int32_t fd) asm("nuc_fd-out");
struct nuc_FdOut nuc_std_out(void) asm("nuc_std-out");
struct nuc_FdOut nuc_std_err(void) asm("nuc_std-err");
/* fd-write-all: uses an error-union or option type; not exported */
/* write-str: uses an error-union or option type; not exported */
extern struct nuc_String nuc_g_io_buf asm("nuc_g-io-buf");
extern int32_t nuc_g_io_buf_ready asm("nuc_g-io-buf-ready");
struct nuc_String* nuc_io_buf_begin(void) asm("nuc_io-buf-begin");
/* io-buf-end: uses an error-union or option type; not exported */
#define IO_IN_CAP 8192
extern void* nuc_g_in_buf asm("nuc_g-in-buf");
extern size_t nuc_g_in_len asm("nuc_g-in-len");
extern size_t nuc_g_in_pos asm("nuc_g-in-pos");
extern int32_t nuc_g_in_eof asm("nuc_g-in-eof");
int32_t nuc_io_in_fill(void) asm("nuc_io-in-fill");
/* read-line: uses an error-union or option type; not exported */
