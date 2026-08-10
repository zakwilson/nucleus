#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/boxlib.nuc by nucleusc --emit-cheader */

struct T box-get(void** b);
void box-set(void** b, struct T v);
