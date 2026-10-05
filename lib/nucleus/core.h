#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/nucleus/core.nuc by nucleusc --emit-cheader */

typedef struct nuc_Symbol {
    uint8_t* p;
} nuc_Symbol;

typedef struct nuc_Node {
    int32_t kind;
    int32_t line;
    int64_t i;
    struct nuc_Symbol s;
    struct nuc_Node** elems;
    int32_t len;
    int32_t cap;
} nuc_Node;

enum NodeKind {
    NodeKind_NODE_INT = 0,
    NodeKind_NODE_STR = 1,
    NodeKind_NODE_SYM = 2,
    NodeKind_NODE_LIST = 3,
    NodeKind_NODE_FLOAT = 4,
    NodeKind_NODE_KEYWORD = 5,
    NodeKind_NODE_CHAR = 6
};

typedef struct nuc_StrView {
    uint8_t* data;
    size_t len;
} nuc_StrView;

