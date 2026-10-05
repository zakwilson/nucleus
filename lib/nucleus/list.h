#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/nucleus/list.nuc by nucleusc --emit-cheader */

void* nuc_cons(void* car, void* cdr);
void* nuc_first(void* n);
void* nuc_rest(void* n);
void* nuc_append_ptr_ptr(void* a, void* b) asm("nuc_append.ptr.ptr");
typedef struct nuc_ListIter {
    void* cur;
} nuc_ListIter;

/* next: uses an error-union or option type; not exported */
struct nuc_ListIter nuc_list_iter(void* lst) asm("nuc_list-iter");
