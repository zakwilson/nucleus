#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/error.nuc by nucleusc --emit-cheader */

typedef struct {
    struct Err what;
    void* rty;
    void* hfn;
    void* ctx;
    void* prev;
} Handler;

extern void* g_handler_top asm("g-handler-top");
void* err_find_handler(struct Err eid, void* token) asm("err-find-handler");
