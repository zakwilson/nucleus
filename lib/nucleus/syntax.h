#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"

/* Generated from lib/nucleus/syntax.nuc by nucleusc --emit-cheader */

enum SynKind {
    SynKind_SYN_ATOM = 0,
    SynKind_SYN_STR = 1,
    SynKind_SYN_CHAR = 2,
    SynKind_SYN_LIST = 3,
    SynKind_SYN_VEC = 4,
    SynKind_SYN_MAP = 5,
    SynKind_SYN_SET = 6,
    SynKind_SYN_PREFIX = 7,
    SynKind_SYN_TAGGED = 8,
    SynKind_SYN_FUSE = 9
};

#ifndef NUC_INST_nuc_dynref_nucleus_allocator_Allocator
#define NUC_INST_nuc_dynref_nucleus_allocator_Allocator
typedef struct nuc_dynref_nucleus_allocator_Allocator {
    void* data;
    const void* vtable;
} nuc_dynref_nucleus_allocator_Allocator;
#endif

#ifndef NUC_INST_nuc_Vector_pnuc_Syn
#define NUC_INST_nuc_Vector_pnuc_Syn
typedef struct nuc_Vector_pnuc_Syn {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_pnuc_Syn;
#endif

typedef struct nuc_Syn {
    int32_t kind;
    size_t start;
    size_t end;
    int32_t line;
    int32_t col;
    int32_t open;
    struct nuc_Node* /* nullable */ node;
    struct nuc_Syn* /* nullable */ parent;
    struct nuc_Vector_pnuc_Syn kids;
} nuc_Syn;

typedef struct nuc_SynSpan {
    size_t start;
    size_t end;
} nuc_SynSpan;

#ifndef NUC_INST_nuc_Vector_nuc_SynSpan
#define NUC_INST_nuc_Vector_nuc_SynSpan
typedef struct nuc_Vector_nuc_SynSpan {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_SynSpan;
#endif

typedef struct nuc_SynFile {
    struct nuc_StrView src;
    struct nuc_Node* tree;
    struct nuc_Vector_pnuc_Syn forms;
    struct nuc_Vector_nuc_SynSpan comments;
    struct nuc_Vector_nuc_SynSpan discards;
    bool fragment;
    bool ends_in_string;
} nuc_SynFile;

typedef struct nuc_SynBuilder {
    struct nuc_SynFile* file;
    struct nuc_Syn* /* nullable */ cur;
    struct nuc_Syn* sink;
    bool framed;
    bool recover;
} nuc_SynBuilder;

int32_t nuc_syn_col(struct nuc_StrView src, size_t at) asm("nuc_syn-col");
struct nuc_Syn* nuc_syn_new(int32_t kind, size_t start, int32_t line, int32_t col) asm("nuc_syn-new");
struct nuc_SynBuilder* nuc_syn_builder_new(struct nuc_StrView src) asm("nuc_syn-builder-new");
struct nuc_Syn* nuc_syn_open(struct nuc_SynBuilder* b, int32_t kind, int32_t open, size_t start, int32_t line) asm("nuc_syn-open");
void nuc_syn_close(struct nuc_SynBuilder* b, struct nuc_Syn* s, size_t end, struct nuc_Node* /* nullable */ n) asm("nuc_syn-close");
void nuc_syn_abandon(struct nuc_SynBuilder* b, struct nuc_Syn* s) asm("nuc_syn-abandon");
void nuc_syn_add_head_kid(struct nuc_Syn* s, size_t start, size_t end, struct nuc_Node* /* nullable */ n) asm("nuc_syn-add-head-kid");
void nuc_syn_comment(struct nuc_SynBuilder* b, size_t start, size_t end) asm("nuc_syn-comment");
struct nuc_Syn* /* nullable */ nuc_syn_discard_begin(struct nuc_SynBuilder* b, size_t start) asm("nuc_syn-discard-begin");
void nuc_syn_discard_end(struct nuc_SynBuilder* b, struct nuc_Syn* /* nullable */ saved, size_t end) asm("nuc_syn-discard-end");
struct nuc_StrView nuc_syn_slice(struct nuc_SynFile* f, size_t start, size_t end) asm("nuc_syn-slice");
struct nuc_StrView nuc_syn_text(struct nuc_SynFile* f, struct nuc_Syn* s) asm("nuc_syn-text");
struct nuc_StrView nuc_syn_prefix(struct nuc_SynFile* f, struct nuc_Syn* s) asm("nuc_syn-prefix");
bool nuc_syn_spans_inside_QMARK(struct nuc_Vector_nuc_SynSpan* spans, struct nuc_Syn* s) asm("nuc_syn-spans-inside_QMARK");
bool nuc_syn_has_comment_QMARK(struct nuc_SynFile* f, struct nuc_Syn* s) asm("nuc_syn-has-comment_QMARK");
bool nuc_syn_has_discard_QMARK(struct nuc_SynFile* f, struct nuc_Syn* s) asm("nuc_syn-has-discard_QMARK");
int32_t nuc_syn_elem_offset(int32_t kind) asm("nuc_syn-elem-offset");
struct nuc_Syn* /* nullable */ nuc_syn_kid_for_node(struct nuc_Syn* s, struct nuc_Node* /* nullable */ n) asm("nuc_syn-kid-for-node");
struct nuc_Syn* /* nullable */ nuc_syn_kid_for_elem(struct nuc_Syn* s, int32_t i) asm("nuc_syn-kid-for-elem");
int32_t nuc_syn_elem_index(struct nuc_Syn* s, struct nuc_Syn* k) asm("nuc_syn-elem-index");
