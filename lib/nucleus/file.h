#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "string.h"
#include "core.h"

/* Generated from lib/nucleus/file.nuc by nucleusc --emit-cheader */

#define MODE_644 420
#define MODE_755 493
#define FILE_CHUNK 65536
typedef struct nuc_File {
    int32_t fd;
} nuc_File;

struct nuc_File nuc_file(int32_t fd);
void nuc_drop_pnuc_File(struct nuc_File* self) asm("nuc_drop.pnuc_File");
/* file-close: uses an error-union or option type; not exported */
/* file-open-flags: uses an error-union or option type; not exported */
/* file-open-read: uses an error-union or option type; not exported */
/* file-create: uses an error-union or option type; not exported */
/* file-open-append: uses an error-union or option type; not exported */
/* file-write-bytes: uses an error-union or option type; not exported */
/* write-str: uses an error-union or option type; not exported */
/* file-read-to-string: uses an error-union or option type; not exported */
#define BUF_WRITER_CAP 65536
typedef struct nuc_BufWriter {
    struct nuc_File out;
    struct nuc_String buf;
} nuc_BufWriter;

struct nuc_BufWriter nuc_buf_writer(struct nuc_File f) asm("nuc_buf-writer");
/* flush: uses an error-union or option type; not exported */
/* write-str: uses an error-union or option type; not exported */
/* buf-writer-close: uses an error-union or option type; not exported */
void nuc_drop_pnuc_BufWriter(struct nuc_BufWriter* self) asm("nuc_drop.pnuc_BufWriter");
#define DIRENT_D_NAME_OFFSET 19
#define DIRENT_D_TYPE_OFFSET 18
#ifndef NUC_INST_nuc_dynref_nucleus_allocator_Allocator
#define NUC_INST_nuc_dynref_nucleus_allocator_Allocator
typedef struct nuc_dynref_nucleus_allocator_Allocator {
    void* data;
    const void* vtable;
} nuc_dynref_nucleus_allocator_Allocator;
#endif

#ifndef NUC_INST_nuc_Vector_usize
#define NUC_INST_nuc_Vector_usize
typedef struct nuc_Vector_usize {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_usize;
#endif

#ifndef NUC_INST_nuc_Vector_u8
#define NUC_INST_nuc_Vector_u8
typedef struct nuc_Vector_u8 {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_u8;
#endif

typedef struct nuc_DirEntries {
    struct nuc_String buf;
    struct nuc_Vector_usize offs;
    struct nuc_Vector_u8 kinds;
} nuc_DirEntries;

struct nuc_DirEntries nuc_dir_entries_new(void) asm("nuc_dir-entries-new");
size_t nuc_dir_count(struct nuc_DirEntries* self) asm("nuc_dir-count");
bool nuc_dir_is_dir_QMARK(struct nuc_DirEntries* self, size_t i) asm("nuc_dir-is-dir_QMARK");
struct nuc_StrView nuc_dir_name(struct nuc_DirEntries* self, size_t i) asm("nuc_dir-name");
void nuc_drop_pnuc_DirEntries(struct nuc_DirEntries* self) asm("nuc_drop.pnuc_DirEntries");
void nuc_dir_push(struct nuc_DirEntries* self, struct nuc_StrView nm, uint8_t kind) asm("nuc_dir-push");
void nuc_dir_sort(struct nuc_DirEntries* self) asm("nuc_dir-sort");
uint8_t nuc_dir_resolve_kind(struct nuc_StrView dir, struct nuc_StrView nm, uint8_t kind) asm("nuc_dir-resolve-kind");
/* read-dir: uses an error-union or option type; not exported */
bool nuc_dir_exists_QMARK(struct nuc_StrView path) asm("nuc_dir-exists_QMARK");
/* make-dir: uses an error-union or option type; not exported */
uint8_t nuc_glob_byte_at(struct nuc_StrView* v, size_t i) asm("nuc_glob-byte-at");
bool nuc_glob_match(struct nuc_StrView* pat, struct nuc_StrView* s) asm("nuc_glob-match");
size_t nuc_path_comp_end(struct nuc_StrView* s, size_t at) asm("nuc_path-comp-end");
struct nuc_StrView nuc_path_comp(struct nuc_StrView* s, size_t at, size_t end) asm("nuc_path-comp");
bool nuc_path_comp_match(struct nuc_StrView* pc, struct nuc_StrView* sc) asm("nuc_path-comp-match");
bool nuc_path_glob_from(struct nuc_StrView* pat, size_t pi, struct nuc_StrView* path, size_t si) asm("nuc_path-glob-from");
bool nuc_path_glob_match(struct nuc_StrView* pat, struct nuc_StrView* path) asm("nuc_path-glob-match");
int32_t nuc_walk_key_tail(struct nuc_StrView* nm, size_t k, bool dir) asm("nuc_walk-key-tail");
bool nuc_walk_less_QMARK(struct nuc_DirEntries* d, size_t a, size_t b) asm("nuc_walk-less_QMARK");
struct nuc_Vector_usize nuc_walk_order(struct nuc_DirEntries* d) asm("nuc_walk-order");
/* walk-into: uses an error-union or option type; not exported */
/* walk-dir: uses an error-union or option type; not exported */
bool nuc_glob_names_hidden_QMARK(struct nuc_StrView* pat, size_t at) asm("nuc_glob-names-hidden_QMARK");
size_t nuc_glob_literal_end(struct nuc_StrView* pat) asm("nuc_glob-literal-end");
bool nuc_path_readable_QMARK(struct nuc_StrView path) asm("nuc_path-readable_QMARK");
/* glob-files: uses an error-union or option type; not exported */
