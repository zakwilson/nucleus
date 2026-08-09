#pragma once
#include <stdint.h>
#include <stdbool.h>

/* Generated from lib/avr.nuc by nucleusc --emit-cheader */

uint8_t reg8-read(struct usize addr);
void reg8-write(struct usize addr, uint8_t val);
uint16_t reg16-read(struct usize addr);
void reg16-write(struct usize addr, uint16_t val);
uint8_t bit-mask(uint8_t bit);
uint8_t reg8-test-bit(struct usize addr, uint8_t bit);
void reg8-set-bit_BANG(struct usize addr, uint8_t bit);
void reg8-clear-bit_BANG(struct usize addr, uint8_t bit);
void reg8-toggle-bit_BANG(struct usize addr, uint8_t bit);
