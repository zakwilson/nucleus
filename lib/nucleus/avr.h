#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/avr.nuc by nucleusc --emit-cheader */

uint8_t reg8_read(size_t addr) asm("reg8-read");
void reg8_write(size_t addr, uint8_t val) asm("reg8-write");
uint16_t reg16_read(size_t addr) asm("reg16-read");
void reg16_write(size_t addr, uint16_t val) asm("reg16-write");
uint8_t bit_mask(uint8_t bit) asm("bit-mask");
uint8_t reg8_test_bit(size_t addr, uint8_t bit) asm("reg8-test-bit");
void reg8_set_bit_BANG(size_t addr, uint8_t bit) asm("reg8-set-bit_BANG");
void reg8_clear_bit_BANG(size_t addr, uint8_t bit) asm("reg8-clear-bit_BANG");
void reg8_toggle_bit_BANG(size_t addr, uint8_t bit) asm("reg8-toggle-bit_BANG");
