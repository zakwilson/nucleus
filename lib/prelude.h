#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/prelude.nuc by nucleusc --emit-cheader */

typedef struct Node {
    int32_t kind;
    int32_t line;
    int64_t i;
    void* s;
    void* car;
    void* cdr;
} Node;

enum NodeKind {
    NodeKind_NODE_INT = 0,
    NodeKind_NODE_STR = 1,
    NodeKind_NODE_SYM = 2,
    NodeKind_NODE_CELL = 3,
    NodeKind_NODE_FLOAT = 4,
    NodeKind_NODE_KEYWORD = 5,
    NodeKind_NODE_CHAR = 6
};

typedef struct StrView {
    uint8_t* data;
    size_t len;
} StrView;

