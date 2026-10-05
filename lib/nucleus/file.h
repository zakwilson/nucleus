#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "string.h"
#include "allocator.h"
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
#ifndef NUC_INST_nuc_Vector_usize
#define NUC_INST_nuc_Vector_usize
typedef struct nuc_Vector_usize {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_AllocHandle alloc;
} nuc_Vector_usize;
#endif

typedef struct nuc_DirEntries {
    struct nuc_String buf;
    struct nuc_Vector_usize offs;
} nuc_DirEntries;

size_t nuc_dir_count(struct nuc_DirEntries* self) asm("nuc_dir-count");
struct nuc_StrView nuc_dir_name(struct nuc_DirEntries* self, size_t i) asm("nuc_dir-name");
void nuc_drop_pnuc_DirEntries(struct nuc_DirEntries* self) asm("nuc_drop.pnuc_DirEntries");
size_t nuc_dir_push_name(struct nuc_DirEntries* self, struct nuc_StrView nm) asm("nuc_dir-push-name");
void nuc_dir_sort(struct nuc_DirEntries* self) asm("nuc_dir-sort");
/* read-dir: uses an error-union or option type; not exported */
bool nuc_dir_exists_QMARK(struct nuc_StrView path) asm("nuc_dir-exists_QMARK");
/* make-dir: uses an error-union or option type; not exported */
