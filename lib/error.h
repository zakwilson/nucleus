#pragma once
#include <stdint.h>
#include <stdbool.h>

/* Generated from lib/error.nuc by nucleusc --emit-cheader */

typedef struct {
    struct Err what;
    void* rty;
    void* hfn;
    void* ctx;
    void* prev;
} Handler;

void* err-find-handler(struct Err eid, void* token);
