#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/avr.nuc by nucleusc --emit-cheader */

uint8_t reg8-read(size_t addr);
void reg8-write(size_t addr, uint8_t val);
uint16_t reg16-read(size_t addr);
void reg16-write(size_t addr, uint16_t val);
uint8_t bit-mask(uint8_t bit);
uint8_t reg8-test-bit(size_t addr, uint8_t bit);
void reg8-set-bit_BANG(size_t addr, uint8_t bit);
void reg8-clear-bit_BANG(size_t addr, uint8_t bit);
void reg8-toggle-bit_BANG(size_t addr, uint8_t bit);
