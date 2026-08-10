#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/hashset.nuc by nucleusc --emit-cheader */

void hashset_oom(void) asm("hashset-oom");
/* hashset-init: generic template; not exported */
/* hashset-init-alloc: generic template; not exported */
/* hashset-new: generic template; not exported */
/* hashset-new-alloc: generic template; not exported */
/* hashset-new-in: generic template; not exported */
/* hashset-resize: generic template; not exported */
/* insert: generic template; not exported */
/* contains?: generic template; not exported */
/* set-remove: generic template; not exported */
/* count: generic template; not exported */
/* empty?: generic template; not exported */
/* conj: generic template; not exported */
/* union: generic template; not exported */
/* difference: generic template; not exported */
/* intersection: generic template; not exported */
/* drop: generic template; not exported */
/* next: generic template; not exported */
/* hashset-iter: generic template; not exported */
/* iter: generic template; not exported */
