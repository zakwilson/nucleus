#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"

/* Generated from lib/nucleus/node.nuc by nucleusc --emit-cheader */

struct Node* alloc_node(void) asm("alloc-node");
struct Node* node_int(int64_t v) asm("node-int");
struct Node* /* nullable */ node_at(struct Node* n, int32_t i) asm("node-at");
int32_t node_len(struct Node* /* nullable */ n) asm("node-len");
int32_t node_line(struct Node* /* nullable */ n, int32_t encl) asm("node-line");
bool node_is_list(struct Node* /* nullable */ n) asm("node-is-list");
bool node_empty_QMARK(struct Node* /* nullable */ n) asm("node-empty_QMARK");
#define NODE_NIL -1
int32_t node_kind(struct Node* n) asm("node-kind");
struct Node* /* nullable */ node_first(struct Node* n) asm("node-first");
struct Node* /* nullable */* /* nullable */ node_elems_alloc(int32_t n) asm("node-elems-alloc");
struct Node* node_list_new(int32_t line) asm("node-list-new");
struct Node* node_rest(struct Node* n) asm("node-rest");
void node_reserve(struct Node* b) asm("node-reserve");
void node_push(struct Node* b, struct Node* /* nullable */ x) asm("node-push");
void node_push_line(struct Node* b, struct Node* /* nullable */ x, int32_t line) asm("node-push-line");
void node_extend(struct Node* b, struct Node* /* nullable */ lst) asm("node-extend");
struct Node* node_list_done(struct Node* b) asm("node-list-done");
struct Node* node_cons(struct Node* /* nullable */ x, struct Node* /* nullable */ lst, int32_t line) asm("node-cons");
void node_set_at(struct Node* lst, int32_t i, struct Node* /* nullable */ x) asm("node-set-at");
void node_splice_at(struct Node* lst, int32_t i, struct Node* /* nullable */ items, struct Node* /* nullable */ extra) asm("node-splice-at");
struct Node* node_list1(struct Node* /* nullable */ a, int32_t line) asm("node-list1");
struct Node* node_list2(struct Node* /* nullable */ a, struct Node* /* nullable */ b, int32_t line) asm("node-list2");
struct Node* node_list3(struct Node* /* nullable */ a, struct Node* /* nullable */ b, struct Node* /* nullable */ c, int32_t line) asm("node-list3");
struct Node* node_list4(struct Node* /* nullable */ a, struct Node* /* nullable */ b, struct Node* /* nullable */ c, struct Node* /* nullable */ d, int32_t line) asm("node-list4");
struct Node* node_list5(struct Node* /* nullable */ a, struct Node* /* nullable */ b, struct Node* /* nullable */ c, struct Node* /* nullable */ d, struct Node* /* nullable */ e, int32_t line) asm("node-list5");
struct Symbol node_head_sym(struct Node* n) asm("node-head-sym");
typedef struct InternEntry {
    struct Symbol spelling;
    struct Node* node;
} InternEntry;

extern void* g_intern_table asm("g-intern-table");
extern int32_t g_intern_cap asm("g-intern-cap");
extern int32_t g_intern_len asm("g-intern-len");
void sym_node_place(void* table, int32_t cap, struct Symbol sp, struct Node* nd, int64_t h) asm("sym-node-place");
void sym_node_grow(void) asm("sym-node-grow");
struct Node* intern_node(struct Symbol sym) asm("intern-node");
struct Node* intern_symbol(const char* s) asm("intern-symbol");
typedef struct NodeIter {
    struct Node* lst;
    int32_t pos;
} NodeIter;

struct Node* /* nullable */ next_pNodeIter(struct NodeIter* self) asm("next.pNodeIter");
size_t count(struct Node* self);
void conj_(struct Node* self, struct Node* elem) asm("conj");
bool empty_QMARK(struct Node* self);
struct NodeIter iter(struct Node* self);
struct Node* invoke(struct Node* self, size_t i);
void append(struct Node* self, struct Node* elem);
bool contains_QMARK(struct Node* self, struct Node* elem);
void insert(struct Node* self, size_t i, struct Node* elem);
