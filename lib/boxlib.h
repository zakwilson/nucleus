#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/boxlib.nuc by nucleusc --emit-cheader */

struct T box_get(void** b) asm("box-get");
void box_set(void** b, struct T v) asm("box-set");
