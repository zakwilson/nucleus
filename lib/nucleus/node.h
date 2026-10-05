#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"

/* Generated from lib/nucleus/node.nuc by nucleusc --emit-cheader */

struct nuc_Node* nuc_alloc_node(void) asm("nuc_alloc-node");
struct nuc_Node* nuc_node_int(int64_t v) asm("nuc_node-int");
struct nuc_Node* /* nullable */ nuc_node_at(struct nuc_Node* n, int32_t i) asm("nuc_node-at");
int32_t nuc_node_len(struct nuc_Node* /* nullable */ n) asm("nuc_node-len");
int32_t nuc_node_line(struct nuc_Node* /* nullable */ n, int32_t encl) asm("nuc_node-line");
bool nuc_node_is_list(struct nuc_Node* /* nullable */ n) asm("nuc_node-is-list");
bool nuc_node_empty_QMARK(struct nuc_Node* /* nullable */ n) asm("nuc_node-empty_QMARK");
#define NODE_NIL -1
int32_t nuc_node_kind(struct nuc_Node* n) asm("nuc_node-kind");
struct nuc_Node* /* nullable */ nuc_node_first(struct nuc_Node* n) asm("nuc_node-first");
struct nuc_Node* /* nullable */* /* nullable */ nuc_node_elems_alloc(int32_t n) asm("nuc_node-elems-alloc");
struct nuc_Node* nuc_node_list_new(int32_t line) asm("nuc_node-list-new");
struct nuc_Node* nuc_node_rest(struct nuc_Node* n) asm("nuc_node-rest");
void nuc_node_reserve(struct nuc_Node* b) asm("nuc_node-reserve");
void nuc_node_push(struct nuc_Node* b, struct nuc_Node* /* nullable */ x) asm("nuc_node-push");
void nuc_node_push_line(struct nuc_Node* b, struct nuc_Node* /* nullable */ x, int32_t line) asm("nuc_node-push-line");
void nuc_node_extend(struct nuc_Node* b, struct nuc_Node* /* nullable */ lst) asm("nuc_node-extend");
struct nuc_Node* nuc_node_list_done(struct nuc_Node* b) asm("nuc_node-list-done");
struct nuc_Node* nuc_node_cons(struct nuc_Node* /* nullable */ x, struct nuc_Node* /* nullable */ lst, int32_t line) asm("nuc_node-cons");
void nuc_node_set_at(struct nuc_Node* lst, int32_t i, struct nuc_Node* /* nullable */ x) asm("nuc_node-set-at");
void nuc_node_splice_at(struct nuc_Node* lst, int32_t i, struct nuc_Node* /* nullable */ items, struct nuc_Node* /* nullable */ extra) asm("nuc_node-splice-at");
struct nuc_Node* nuc_node_list1(struct nuc_Node* /* nullable */ a, int32_t line) asm("nuc_node-list1");
struct nuc_Node* nuc_node_list2(struct nuc_Node* /* nullable */ a, struct nuc_Node* /* nullable */ b, int32_t line) asm("nuc_node-list2");
struct nuc_Node* nuc_node_list3(struct nuc_Node* /* nullable */ a, struct nuc_Node* /* nullable */ b, struct nuc_Node* /* nullable */ c, int32_t line) asm("nuc_node-list3");
struct nuc_Node* nuc_node_list4(struct nuc_Node* /* nullable */ a, struct nuc_Node* /* nullable */ b, struct nuc_Node* /* nullable */ c, struct nuc_Node* /* nullable */ d, int32_t line) asm("nuc_node-list4");
struct nuc_Node* nuc_node_list5(struct nuc_Node* /* nullable */ a, struct nuc_Node* /* nullable */ b, struct nuc_Node* /* nullable */ c, struct nuc_Node* /* nullable */ d, struct nuc_Node* /* nullable */ e, int32_t line) asm("nuc_node-list5");
struct nuc_Symbol nuc_node_head_sym(struct nuc_Node* n) asm("nuc_node-head-sym");
typedef struct nuc_InternEntry {
    struct nuc_Symbol spelling;
    struct nuc_Node* node;
} nuc_InternEntry;

extern void* nuc_g_intern_table asm("nuc_g-intern-table");
extern int32_t nuc_g_intern_cap asm("nuc_g-intern-cap");
extern int32_t nuc_g_intern_len asm("nuc_g-intern-len");
void nuc_sym_node_place(void* table, int32_t cap, struct nuc_Symbol sp, struct nuc_Node* nd, int64_t h) asm("nuc_sym-node-place");
void nuc_sym_node_grow(void) asm("nuc_sym-node-grow");
struct nuc_Node* nuc_intern_node(struct nuc_Symbol sym) asm("nuc_intern-node");
struct nuc_Node* nuc_intern_symbol(const char* s) asm("nuc_intern-symbol");
typedef struct nuc_NodeIter {
    struct nuc_Node* lst;
    int32_t pos;
} nuc_NodeIter;

struct nuc_Node* /* nullable */ nuc_next_pnuc_NodeIter(struct nuc_NodeIter* self) asm("nuc_next.pnuc_NodeIter");
size_t nuc_count(struct nuc_Node* self);
void nuc_conj(struct nuc_Node* self, struct nuc_Node* elem);
bool nuc_empty_QMARK(struct nuc_Node* self);
struct nuc_NodeIter nuc_iter(struct nuc_Node* self);
struct nuc_Node* nuc_invoke(struct nuc_Node* self, size_t i);
void nuc_append(struct nuc_Node* self, struct nuc_Node* elem);
bool nuc_contains_QMARK(struct nuc_Node* self, struct nuc_Node* elem);
void nuc_insert(struct nuc_Node* self, size_t i, struct nuc_Node* elem);
