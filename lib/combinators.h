#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/combinators.nuc by nucleusc --emit-cheader */

/* map: generic template; not exported */
/* filter: generic template; not exported */
/* remove-if: generic template; not exported */
/* for-each: generic template; not exported */
/* flat-map: generic template; not exported */
/* find: generic template; not exported */
/* find-index: generic template; not exported */
/* any?: generic template; not exported */
/* exists?: generic template; not exported */
/* every?: generic template; not exported */
/* all?: generic template; not exported */
/* count-if: generic template; not exported */
/* foldr: generic template; not exported */
/* sum: generic template; not exported */
/* product: generic template; not exported */
/* min: generic template; not exported */
/* max: generic template; not exported */
/* sort: generic template; not exported */
/* sort-by: generic template; not exported */
/* emit-joined: generic template; not exported */
void join_push_cstr(void* s, const char* cs) asm("join-push-cstr");
/* join: generic template; not exported */
/* keep-last: generic template; not exported */
/* compose: generic template; not exported */
/* comp: generic template; not exported */
/* complement: generic template; not exported */
/* conjoin: generic template; not exported */
/* disjoin: generic template; not exported */
/* constantly: generic template; not exported */
/* partial: generic template; not exported */
