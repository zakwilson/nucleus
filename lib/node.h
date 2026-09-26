#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"

/* Generated from lib/node.nuc by nucleusc --emit-cheader */

struct Node* alloc_node(void) asm("alloc-node");
struct Node* node_int(int64_t v) asm("node-int");
struct Node* /* niche: reserved top page = error/none */ node_at(void* n, int32_t i) asm("node-at");
int32_t node_len(void* n) asm("node-len");
int32_t node_line(void* n, int32_t encl) asm("node-line");
bool node_is_list(void* n) asm("node-is-list");
bool node_empty_QMARK(void* n) asm("node-empty_QMARK");
#define NODE_NIL -1
int32_t node_kind(void* n) asm("node-kind");
void* node_first(void* n) asm("node-first");
void* node_elems_alloc(int32_t n) asm("node-elems-alloc");
struct Node* node_list_new(int32_t line) asm("node-list-new");
void* node_rest(void* n) asm("node-rest");
void node_reserve(struct Node* b) asm("node-reserve");
void node_push(struct Node* b, void* x) asm("node-push");
void node_push_line(struct Node* b, void* x, int32_t line) asm("node-push-line");
void node_extend(struct Node* b, void* lst) asm("node-extend");
void* node_list_done(struct Node* b) asm("node-list-done");
struct Node* node_cons(void* x, void* lst, int32_t line) asm("node-cons");
void node_set_at(struct Node* lst, int32_t i, void* x) asm("node-set-at");
void node_splice_at(struct Node* lst, int32_t i, void* items, void* extra) asm("node-splice-at");
struct Node* node_list1(void* a, int32_t line) asm("node-list1");
struct Node* node_list2(void* a, void* b, int32_t line) asm("node-list2");
struct Node* node_list3(void* a, void* b, void* c, int32_t line) asm("node-list3");
struct Node* node_list4(void* a, void* b, void* c, void* d, int32_t line) asm("node-list4");
struct Node* node_list5(void* a, void* b, void* c, void* d, void* e, int32_t line) asm("node-list5");
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
    void* lst;
    int32_t pos;
} NodeIter;

struct Node* /* niche: reserved top page = error/none */ next_pNodeIter(struct NodeIter* self) asm("next.pNodeIter");
size_t count(struct Node* self);
void conj_(struct Node* self, struct Node* elem) asm("conj");
bool empty_QMARK(struct Node* self);
struct NodeIter iter(struct Node* self);
struct Node* invoke(struct Node* self, size_t i);
void append(struct Node* self, struct Node* elem);
bool contains_QMARK(struct Node* self, struct Node* elem);
void insert(struct Node* self, size_t i, struct Node* elem);
