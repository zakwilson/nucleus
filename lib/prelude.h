#pragma once
#include <stdint.h>
#include <stdbool.h>

/* Generated from lib/prelude.nuc by nucleusc --emit-cheader */

typedef struct {
    int32_t kind;
    int32_t line;
    int64_t i;
    void* s;
    void* car;
    void* cdr;
} Node;

enum NodeKind {
    NodeKind_NODE-INT = 0,
    NodeKind_NODE-STR = 1,
    NodeKind_NODE-SYM = 2,
    NodeKind_NODE-CELL = 3,
    NodeKind_NODE-FLOAT = 4,
    NodeKind_NODE-KEYWORD = 5,
    NodeKind_NODE-CHAR = 6
};

typedef struct {
    uint8_t* data;
    struct usize len;
} StrView;

