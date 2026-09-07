#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "string.h"

/* Generated from lib/io.nuc by nucleusc --emit-cheader */

typedef struct FdOut {
    int32_t fd;
} FdOut;

struct FdOut fd_out(int32_t fd) asm("fd-out");
struct FdOut std_out(void) asm("std-out");
struct FdOut std_err(void) asm("std-err");
/* fd-write-all: uses an error-union or option type; not exported */
/* write-str: uses an error-union or option type; not exported */
extern struct String g_io_buf asm("g-io-buf");
extern int32_t g_io_buf_ready asm("g-io-buf-ready");
struct String* io_buf_begin(void) asm("io-buf-begin");
/* io-buf-end: uses an error-union or option type; not exported */
#define IO_IN_CAP 8192
extern void* g_in_buf asm("g-in-buf");
extern size_t g_in_len asm("g-in-len");
extern size_t g_in_pos asm("g-in-pos");
extern int32_t g_in_eof asm("g-in-eof");
int32_t io_in_fill(void) asm("io-in-fill");
/* read-line: uses a defunion-template instance type; not exported */
