#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"

/* Generated from lib/nucleus/vector.nuc by nucleusc --emit-cheader */

void nuc_vector_oom(void) asm("nuc_vector-oom");
void nuc_vector_bounds(struct nuc_StrView what, size_t i, size_t n) asm("nuc_vector-bounds");
/* init: generic template; not exported */
/* vector-grow: generic template; not exported */
/* count: generic template; not exported */
/* conj: generic template; not exported */
/* empty?: generic template; not exported */
/* invoke: generic template; not exported */
/* set: generic template; not exported */
/* append: generic template; not exported */
/* contains?: generic template; not exported */
/* insert: generic template; not exported */
/* remove-at: generic template; not exported */
/* capacity: generic template; not exported */
/* reserve: generic template; not exported */
/* vector-extend-raw: generic template; not exported */
/* vector-extend: generic template; not exported */
/* init: generic template; not exported */
/* init: generic template; not exported */
/* drop: generic template; not exported */
/* next: generic template; not exported */
/* iter-init: generic template; not exported */
/* iter: generic template; not exported */
