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

extern bool g_test_no_skip asm("g-test-no-skip");
/* TestCase: a field uses an error-union or option type; not exported */
struct TestCase;
extern struct AllocHandle g_test_alloc asm("g-test-alloc");
#ifndef NUC_INST_Vector_TestCase
#define NUC_INST_Vector_TestCase
typedef struct Vector_TestCase {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct AllocHandle alloc;
} Vector_TestCase;
#endif

extern struct Vector_TestCase* g_tests asm("g-tests");
extern struct String g_fail_buf asm("g-fail-buf");
extern int32_t g_fail_ready asm("g-fail-ready");
/* test-add: uses an error-union or option type; not exported */
/* test-register: uses an error-union or option type; not exported */
struct String* test_fail_begin(void) asm("test-fail-begin");
struct StrView test_failure_text(void) asm("test-failure-text");
size_t test_failure_len(void) asm("test-failure-len");
#define SHOW_LIMIT 400
struct StrView test_show(struct StrView s) asm("test-show");
uint8_t test_byte_at(struct StrView* v, size_t i) asm("test-byte-at");
bool glob_match(struct StrView* pat, struct StrView* s) asm("glob-match");
bool contains_QMARK_StrView_StrView(struct StrView hay, struct StrView needle) asm("contains_QMARK.StrView.StrView");
bool has_line_QMARK(struct StrView hay, struct StrView want) asm("has-line_QMARK");
bool has_matching_line_QMARK(struct StrView hay, struct StrView pat) asm("has-matching-line_QMARK");
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
#ifndef NUC_INST_Vector_StrView
#define NUC_INST_Vector_StrView
typedef struct Vector_StrView {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct AllocHandle alloc;
} Vector_StrView;
#endif

typedef struct Diagnostic {
    struct Keyword severity;
    struct StrView file;
    int32_t line;
    struct StrView message;
    struct Vector_StrView* notes;
} Diagnostic;

/* diag-of-node: uses an error-union or option type; not exported */
/* read-diagnostics: uses an error-union or option type; not exported */
#ifndef NUC_INST_Vector_Diagnostic
#define NUC_INST_Vector_Diagnostic
typedef struct Vector_Diagnostic {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct AllocHandle alloc;
} Vector_Diagnostic;
#endif

struct String diag_list_text(struct Vector_Diagnostic* ds) asm("diag-list-text");
bool diag_matches(struct Diagnostic* d, struct StrView severity, struct StrView file, int32_t line, struct StrView needle) asm("diag-matches");
/* check-diagnostic: uses an error-union or option type; not exported */
/* check-error-at: uses an error-union or option type; not exported */
/* check-warning-at: uses an error-union or option type; not exported */
/* check-error-anywhere: uses an error-union or option type; not exported */
/* check-note-at: uses an error-union or option type; not exported */
/* check-note-anywhere: uses an error-union or option type; not exported */
/* check-no-line-zero: uses an error-union or option type; not exported */
/* check-no-errors: uses an error-union or option type; not exported */
typedef struct Quoted {
    struct StrView v;
} Quoted;

struct Quoted quoted(struct StrView v);
/* to-str: uses an error-union or option type; not exported */
void test_report(struct TestCase* tc, int32_t status) asm("test-report");
extern struct StrView g_test_scratch asm("g-test-scratch");
void test_scratch_set(struct StrView name) asm("test-scratch-set");
/* test-scratch: uses an error-union or option type; not exported */
/* test-scratch-sub: uses an error-union or option type; not exported */
/* test-write-file: uses an error-union or option type; not exported */
int32_t test_run_one(struct TestCase* tc) asm("test-run-one");
/* test-find: uses an error-union or option type; not exported */
int32_t test_run_all(size_t shard, size_t nshards) asm("test-run-all");
struct Symbol test_duplicate_name(void) asm("test-duplicate-name");
void test_list(void) asm("test-list");
/* test-parse-shard: uses an error-union or option type; not exported */
int32_t test_main(int32_t argc, void* argv) asm("test-main");
