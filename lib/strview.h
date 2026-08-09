#pragma once
#include <stdint.h>
#include <stdbool.h>

/* Generated from lib/strview.nuc by nucleusc --emit-cheader */

struct usize strview-len(void* sv);
int32_t strview-eq(void* a, void* b);
typedef struct {
    uint8_t* buf;
    struct usize pos;
    struct usize len;
} ByteIter;

void* next(void* self);
struct usize strview-hash(void* sv);
struct StrView* strview-from-cstr(const char* cs);
const char* strview-to-cstr(void* sv);
struct usize hash(void* self);
_Bool =(struct StrView a, struct StrView b);
_Bool _BANG=(struct StrView a, struct StrView b);
typedef struct {
    uint8_t* buf;
    struct usize pos;
    struct usize len;
} CharIter;

void* next(void* self);
struct usize strview-byte-len(void* sv);
struct _BANGui8 strview-byte-at(void* sv, struct usize i);
struct ByteIter strview-bytes(void* sv);
struct StrView strview-as-view(void* sv);
struct ByteIter cstr-bytes(const char* cs);
struct CharIter cstr-chars(const char* cs);
void* strview-sub-bytes(void* sv, struct usize start, struct usize end);
void* strview-byte-find(void* sv, void* needle);
struct usize strview-char-count(void* sv);
struct _BANGChar strview-char-at(void* sv, struct usize i);
struct CharIter strview-chars(void* sv);
int32_t strview-empty(void* sv);
int32_t strview-starts-with(void* sv, void* prefix);
int32_t strview-ends-with(void* sv, void* suffix);
int32_t strview-contains-str(void* sv, void* needle);
int32_t strview-is-ascii-ws(uint8_t b);
struct StrView strview-trim-start(void* sv);
struct StrView strview-trim-end(void* sv);
struct StrView strview-trim(void* sv);
int32_t strview-cmp-raw(void* a, void* b);
_Bool <(struct StrView a, struct StrView b);
_Bool <=(struct StrView a, struct StrView b);
_Bool >(struct StrView a, struct StrView b);
_Bool >=(struct StrView a, struct StrView b);
