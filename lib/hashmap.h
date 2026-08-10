#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/hashmap.nuc by nucleusc --emit-cheader */

void hashmap_oom(void) asm("hashmap-oom");
/* hashmap-init: generic template; not exported */
/* hashmap-init-alloc: generic template; not exported */
/* hashmap-new: generic template; not exported */
/* hashmap-new-alloc: generic template; not exported */
/* hashmap-new-in: generic template; not exported */
/* hashmap-resize: generic template; not exported */
/* assoc: generic template; not exported */
/* dissoc: generic template; not exported */
/* get: generic template; not exported */
/* count: generic template; not exported */
/* empty?: generic template; not exported */
/* conj: generic template; not exported */
/* drop: generic template; not exported */
/* next: generic template; not exported */
/* hmap-iter-keys: generic template; not exported */
/* next: generic template; not exported */
/* hmap-iter-vals: generic template; not exported */
/* keys: generic template; not exported */
/* vals: generic template; not exported */
/* next: generic template; not exported */
/* hmap-iter-entries: generic template; not exported */
/* iter: generic template; not exported */
