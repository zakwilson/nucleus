#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "string.h"

/* Generated from lib/file.nuc by nucleusc --emit-cheader */

#define MODE_644 420
#define FILE_CHUNK 65536
typedef struct File {
    int32_t fd;
} File;

struct File file(int32_t fd);
void drop_pFile(struct File* self) asm("drop.pFile");
/* file-close: uses an error-union or option type; not exported */
/* file-open-flags: uses an error-union or option type; not exported */
/* file-open-read: uses an error-union or option type; not exported */
/* file-create: uses an error-union or option type; not exported */
/* file-open-append: uses an error-union or option type; not exported */
/* file-write-bytes: uses an error-union or option type; not exported */
/* write-str: uses an error-union or option type; not exported */
/* file-read-to-string: uses an error-union or option type; not exported */
#define BUF_WRITER_CAP 65536
typedef struct BufWriter {
    struct File out;
    struct String buf;
} BufWriter;

struct BufWriter buf_writer(struct File f) asm("buf-writer");
/* flush: uses an error-union or option type; not exported */
/* write-str: uses an error-union or option type; not exported */
/* buf-writer-close: uses an error-union or option type; not exported */
void drop_pBufWriter(struct BufWriter* self) asm("drop.pBufWriter");
