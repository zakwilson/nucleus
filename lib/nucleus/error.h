#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/nucleus/error.nuc by nucleusc --emit-cheader */

typedef struct nuc_Handler {
    int32_t what;
    void* rty;
    void* hfn;
    void* ctx;
    void* prev;
} nuc_Handler;

extern void* nuc_g_handler_top asm("nuc_g-handler-top");
void* nuc_err_find_handler(int32_t eid, void* token) asm("nuc_err-find-handler");
