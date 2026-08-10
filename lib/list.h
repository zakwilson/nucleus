#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/list.nuc by nucleusc --emit-cheader */

void* cons(void* car, void* cdr);
void* first(void* n);
void* rest(void* n);
void* append(void* a, void* b);
typedef struct {
    void* cur;
} ListIter;

void* next(void* self);
struct ListIter list_iter(void* lst) asm("list-iter");
