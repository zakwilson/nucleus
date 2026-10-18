#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"

/* Generated from lib/nucleus/slots.nuc by nucleusc --emit-cheader */

enum SlotKind {
    SlotKind_SLOT_UNKNOWN = 0,
    SlotKind_SLOT_TOP = 1,
    SlotKind_SLOT_HEAD = 2,
    SlotKind_SLOT_VALUE = 3,
    SlotKind_SLOT_PLACE = 4,
    SlotKind_SLOT_INLINE = 5,
    SlotKind_SLOT_NAME = 6,
    SlotKind_SLOT_BINDER = 7,
    SlotKind_SLOT_FIELD = 8,
    SlotKind_SLOT_ATTR = 9,
    SlotKind_SLOT_BINDINGS = 10,
    SlotKind_SLOT_PARAMS = 11,
    SlotKind_SLOT_DECL_PARAMS = 12,
    SlotKind_SLOT_OPTIONAL = 13,
    SlotKind_SLOT_RETURN = 14,
    SlotKind_SLOT_TYPE = 15,
    SlotKind_SLOT_TYPES = 16,
    SlotKind_SLOT_SIG = 17,
    SlotKind_SLOT_ARM = 18,
    SlotKind_SLOT_CLAUSE = 19,
    SlotKind_SLOT_PATTERN = 20,
    SlotKind_SLOT_QUOTED = 21,
    SlotKind_SLOT_TEMPLATE = 22
};

typedef struct nuc_FormSlots {
    int32_t a;
    int32_t b;
    int32_t c;
    int32_t rest;
    bool attrs;
    bool desugar;
} nuc_FormSlots;

struct nuc_FormSlots nuc_form_slots_of(struct nuc_StrView h) asm("nuc_form-slots-of");
struct nuc_StrView nuc_slot_head(struct nuc_Node* /* nullable */ n) asm("nuc_slot-head");
struct nuc_FormSlots nuc_form_slots(struct nuc_Node* /* nullable */ n) asm("nuc_form-slots");
int32_t nuc_slot_of_elem(int32_t own, struct nuc_Node* /* nullable */ n, int32_t i) asm("nuc_slot-of-elem");
bool nuc_slots_desugared_QMARK(struct nuc_Node* /* nullable */ n) asm("nuc_slots-desugared_QMARK");
struct nuc_StrView nuc_slot_name(int32_t k) asm("nuc_slot-name");
