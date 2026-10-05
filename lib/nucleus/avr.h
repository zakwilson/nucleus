#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/nucleus/avr.nuc by nucleusc --emit-cheader */

uint8_t nuc_reg8_read(size_t addr) asm("nuc_reg8-read");
void nuc_reg8_write(size_t addr, uint8_t val) asm("nuc_reg8-write");
uint16_t nuc_reg16_read(size_t addr) asm("nuc_reg16-read");
void nuc_reg16_write(size_t addr, uint16_t val) asm("nuc_reg16-write");
uint8_t nuc_bit_mask(uint8_t bit) asm("nuc_bit-mask");
uint8_t nuc_reg8_test_bit(size_t addr, uint8_t bit) asm("nuc_reg8-test-bit");
void nuc_reg8_set_bit_BANG(size_t addr, uint8_t bit) asm("nuc_reg8-set-bit_BANG");
void nuc_reg8_clear_bit_BANG(size_t addr, uint8_t bit) asm("nuc_reg8-clear-bit_BANG");
void nuc_reg8_toggle_bit_BANG(size_t addr, uint8_t bit) asm("nuc_reg8-toggle-bit_BANG");
