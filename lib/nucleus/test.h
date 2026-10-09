#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"
#include "allocator.h"
#include "string.h"
#include "keyword.h"

/* Generated from lib/nucleus/test.nuc by nucleusc --emit-cheader */

enum TestStatus {
    TestStatus_TEST_PASS = 0,
    TestStatus_TEST_FAIL = 1,
    TestStatus_TEST_SKIP = 2
};

extern bool nuc_g_test_no_skip asm("nuc_g-test-no-skip");
/* nuc_TestCase: a field uses an error-union or option type; not exported */
struct nuc_TestCase;
#ifndef NUC_INST_nuc_Vector_nuc_TestCase
#define NUC_INST_nuc_Vector_nuc_TestCase
typedef struct nuc_Vector_nuc_TestCase {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_Alloc alloc;
} nuc_Vector_nuc_TestCase;
#endif

struct nuc_Vector_nuc_TestCase* nuc_test_cases_new(void) asm("nuc_test-cases-new");
extern struct nuc_Vector_nuc_TestCase* nuc_g_tests asm("nuc_g-tests");
extern struct nuc_String nuc_g_fail_buf asm("nuc_g-fail-buf");
extern int32_t nuc_g_fail_ready asm("nuc_g-fail-ready");
/* test-add: uses an error-union or option type; not exported */
/* test-register: uses an error-union or option type; not exported */
struct nuc_String* nuc_test_fail_begin(void) asm("nuc_test-fail-begin");
struct nuc_StrView nuc_test_failure_text(void) asm("nuc_test-failure-text");
size_t nuc_test_failure_len(void) asm("nuc_test-failure-len");
#define SHOW_LIMIT 400
struct nuc_StrView nuc_test_show(struct nuc_StrView s) asm("nuc_test-show");
uint8_t nuc_test_byte_at(struct nuc_StrView* v, size_t i) asm("nuc_test-byte-at");
bool nuc_glob_match(struct nuc_StrView* pat, struct nuc_StrView* s) asm("nuc_glob-match");
bool nuc_contains_QMARK_nuc_StrView_nuc_StrView(struct nuc_StrView hay, struct nuc_StrView needle) asm("nuc_contains_QMARK.nuc_StrView.nuc_StrView");
bool nuc_has_line_QMARK(struct nuc_StrView hay, struct nuc_StrView want) asm("nuc_has-line_QMARK");
bool nuc_has_matching_line_QMARK(struct nuc_StrView hay, struct nuc_StrView pat) asm("nuc_has-matching-line_QMARK");
/* check-contains: uses an error-union or option type; not exported */
/* check-not-contains: uses an error-union or option type; not exported */
/* check-line: uses an error-union or option type; not exported */
/* check-eq: uses an error-union or option type; not exported */
/* check-match: uses an error-union or option type; not exported */
/* check-not-match: uses an error-union or option type; not exported */
/* read-file: uses an error-union or option type; not exported */
/* check-golden: uses an error-union or option type; not exported */
/* check-files-eq: uses an error-union or option type; not exported */
/* check-empty: uses an error-union or option type; not exported */
/* check-non-empty: uses an error-union or option type; not exported */
/* check: uses an error-union or option type; not exported */
/* check-eq-int: uses an error-union or option type; not exported */
/* ir-define: uses an error-union or option type; not exported */
/* check-in-define: uses an error-union or option type; not exported */
/* check-not-in-define: uses an error-union or option type; not exported */
#ifndef NUC_INST_nuc_Vector_nuc_StrView
#define NUC_INST_nuc_Vector_nuc_StrView
typedef struct nuc_Vector_nuc_StrView {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_Alloc alloc;
} nuc_Vector_nuc_StrView;
#endif

typedef struct nuc_Diagnostic {
    struct nuc_Keyword severity;
    struct nuc_StrView file;
    int32_t line;
    struct nuc_StrView message;
    struct nuc_Vector_nuc_StrView* notes;
} nuc_Diagnostic;

struct nuc_Vector_nuc_StrView* nuc_test_notes_new(void) asm("nuc_test-notes-new");
/* diag-of-node: uses an error-union or option type; not exported */
/* read-diagnostics: uses an error-union or option type; not exported */
#ifndef NUC_INST_nuc_Vector_nuc_Diagnostic
#define NUC_INST_nuc_Vector_nuc_Diagnostic
typedef struct nuc_Vector_nuc_Diagnostic {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_Alloc alloc;
} nuc_Vector_nuc_Diagnostic;
#endif

struct nuc_String nuc_diag_list_text(struct nuc_Vector_nuc_Diagnostic* ds) asm("nuc_diag-list-text");
bool nuc_diag_matches(struct nuc_Diagnostic* d, struct nuc_StrView severity, struct nuc_StrView file, int32_t line, struct nuc_StrView needle) asm("nuc_diag-matches");
/* check-diagnostic: uses an error-union or option type; not exported */
/* check-error-at: uses an error-union or option type; not exported */
/* check-warning-at: uses an error-union or option type; not exported */
/* check-error-anywhere: uses an error-union or option type; not exported */
/* check-note-at: uses an error-union or option type; not exported */
/* check-note-anywhere: uses an error-union or option type; not exported */
/* check-no-line-zero: uses an error-union or option type; not exported */
/* check-no-errors: uses an error-union or option type; not exported */
typedef struct nuc_Quoted {
    struct nuc_StrView v;
} nuc_Quoted;

struct nuc_Quoted nuc_quoted(struct nuc_StrView v);
/* to-str: uses an error-union or option type; not exported */
void nuc_test_report(struct nuc_TestCase* tc, int32_t status) asm("nuc_test-report");
extern struct nuc_StrView nuc_g_test_scratch asm("nuc_g-test-scratch");
void nuc_test_scratch_set(struct nuc_StrView name) asm("nuc_test-scratch-set");
/* test-scratch: uses an error-union or option type; not exported */
/* test-scratch-sub: uses an error-union or option type; not exported */
/* test-write-file: uses an error-union or option type; not exported */
int32_t nuc_test_run_one(struct nuc_TestCase* tc) asm("nuc_test-run-one");
/* test-find: uses an error-union or option type; not exported */
int32_t nuc_test_run_all(size_t shard, size_t nshards) asm("nuc_test-run-all");
struct nuc_Symbol nuc_test_duplicate_name(void) asm("nuc_test-duplicate-name");
void nuc_test_list(void) asm("nuc_test-list");
/* test-parse-shard: uses an error-union or option type; not exported */
int32_t nuc_test_main(int32_t argc, void* argv) asm("nuc_test-main");
