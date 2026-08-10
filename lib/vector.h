#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/vector.nuc by nucleusc --emit-cheader */

void vector_oom(void) asm("vector-oom");
void vector_bounds(const char* what, size_t i, size_t n) asm("vector-bounds");
/* vector-init: generic template; not exported */
/* vector-init-alloc: generic template; not exported */
/* vector-new: generic template; not exported */
/* vector-new-alloc: generic template; not exported */
/* vector-new-capacity: generic template; not exported */
/* vector-new-in: generic template; not exported */
/* vector-grow: generic template; not exported */
/* count: generic template; not exported */
/* conj: generic template; not exported */
/* empty?: generic template; not exported */
/* invoke: generic template; not exported */
/* append: generic template; not exported */
/* contains?: generic template; not exported */
/* insert: generic template; not exported */
/* remove-at: generic template; not exported */
/* capacity: generic template; not exported */
/* reserve: generic template; not exported */
/* vector-init-capacity: generic template; not exported */
/* drop: generic template; not exported */
/* next: generic template; not exported */
/* iter-init: generic template; not exported */
/* iter: generic template; not exported */
