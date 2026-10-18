#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "string.h"
#include "core.h"
#include "syntax.h"
#include "read.h"

/* Generated from lib/nucleus/refactor.nuc by nucleusc --emit-cheader */

typedef struct nuc_Edit {
    size_t start;
    size_t end;
    size_t at;
    size_t len;
} nuc_Edit;

#ifndef NUC_INST_nuc_dynref_nucleus_allocator_Allocator
#define NUC_INST_nuc_dynref_nucleus_allocator_Allocator
typedef struct nuc_dynref_nucleus_allocator_Allocator {
    void* data;
    const void* vtable;
} nuc_dynref_nucleus_allocator_Allocator;
#endif

#ifndef NUC_INST_nuc_Vector_nuc_Edit
#define NUC_INST_nuc_Vector_nuc_Edit
typedef struct nuc_Vector_nuc_Edit {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_Edit;
#endif

typedef struct nuc_Edits {
    struct nuc_String buf;
    struct nuc_Vector_nuc_Edit list;
    bool sorted;
    size_t checked;
} nuc_Edits;

typedef struct nuc_EditError {
    int32_t code;
    struct nuc_StrView msg;
    struct nuc_SynSpan first;
    struct nuc_SynSpan second;
} nuc_EditError;

int32_t nuc_edit_error_code(struct nuc_EditError e) asm("nuc_edit-error-code");
typedef struct nuc_EditsResult {
    int32_t tag;
    union {
        struct nuc_String ok;
        struct nuc_EditError err;
    } payload;
} nuc_EditsResult;

enum nuc_EditsResult_tag {
    nuc_EditsResult_ok = 0,
    nuc_EditsResult_err = 1
};

struct nuc_Edits nuc_edits_new(void) asm("nuc_edits-new");
void nuc_drop_pnuc_Edits(struct nuc_Edits* self) asm("nuc_drop.pnuc_Edits");
size_t nuc_edits_count(struct nuc_Edits* e) asm("nuc_edits-count");
bool nuc_edit_before_QMARK(struct nuc_Edit a, struct nuc_Edit b) asm("nuc_edit-before_QMARK");
void nuc_edit_span(struct nuc_Edits* e, size_t start, size_t end, struct nuc_StrView text) asm("nuc_edit-span");
void nuc_edit_replace(struct nuc_Edits* e, struct nuc_Syn* s, struct nuc_StrView text) asm("nuc_edit-replace");
struct nuc_StrView nuc_edit_text(struct nuc_Edits* e, struct nuc_Edit ed) asm("nuc_edit-text");
void nuc_edits_merge_sort(struct nuc_Vector_nuc_Edit* a, struct nuc_Vector_nuc_Edit* tmp, size_t lo, size_t hi) asm("nuc_edits-merge-sort");
void nuc_edits_sort(struct nuc_Edits* e) asm("nuc_edits-sort");
size_t nuc_edits_drop_within(struct nuc_Edits* e, size_t start, size_t end) asm("nuc_edits-drop-within");
struct nuc_StrView nuc_edit_slice(struct nuc_StrView src, size_t start, size_t end) asm("nuc_edit-slice");
struct nuc_StrView nuc_edit_arena_str(struct nuc_String* s) asm("nuc_edit-arena-str");
void nuc_edit_describe(struct nuc_String* out, struct nuc_StrView src, struct nuc_SynSpan sp) asm("nuc_edit-describe");
struct nuc_EditError nuc_edit_error(int32_t code, struct nuc_StrView src, struct nuc_StrView what, struct nuc_SynSpan a, struct nuc_StrView rel, struct nuc_SynSpan b) asm("nuc_edit-error");
struct nuc_SynSpan nuc_edit_span_of(struct nuc_Edit ed) asm("nuc_edit-span-of");
bool nuc_edits_check(struct nuc_StrView src, struct nuc_Edits* e, struct nuc_EditError* out) asm("nuc_edits-check");
size_t nuc_edits_first_from(struct nuc_Vector_nuc_Edit* l, size_t start) asm("nuc_edits-first-from");
struct nuc_EditsResult nuc_edits_apply_range(struct nuc_StrView src, struct nuc_Edits* e, size_t start, size_t end) asm("nuc_edits-apply-range");
size_t nuc_edits_first_at(struct nuc_Vector_nuc_Edit* l, size_t start) asm("nuc_edits-first-at");
struct nuc_EditsResult nuc_edits_apply_outermost(struct nuc_StrView src, struct nuc_Edits* e, size_t start, size_t end) asm("nuc_edits-apply-outermost");
struct nuc_EditsResult nuc_edits_apply(struct nuc_StrView src, struct nuc_Edits* e) asm("nuc_edits-apply");
enum RuleKind {
    RuleKind_RULE_TEMPLATE = 0,
    RuleKind_RULE_REFUSE = 1,
    RuleKind_RULE_EMIT = 2
};

enum HoleLines {
    HoleLines_LINES_REFUSE = 0,
    HoleLines_LINES_KEEP = 1,
    HoleLines_LINES_SHIFT = 2
};

typedef struct nuc_RwHole {
    struct nuc_Syn* /* nullable */ syn;
    struct nuc_Syn* /* nullable */ list;
    int32_t from;
    bool splice;
} nuc_RwHole;

#ifndef NUC_INST_nuc_Vector_nuc_RwHole
#define NUC_INST_nuc_Vector_nuc_RwHole
typedef struct nuc_Vector_nuc_RwHole {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_RwHole;
#endif

#ifndef NUC_INST_nuc_Vector_nuc_SynSpan
#define NUC_INST_nuc_Vector_nuc_SynSpan
typedef struct nuc_Vector_nuc_SynSpan {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_SynSpan;
#endif

typedef struct nuc_RwMatch {
    struct nuc_Syn* /* nullable */ form;
    struct nuc_Node* /* nullable */ names;
    struct nuc_Vector_nuc_RwHole holes;
    int32_t lines;
    struct nuc_String text;
    struct nuc_Vector_nuc_SynSpan kept;
    int32_t col0;
    struct nuc_StrView refusal;
} nuc_RwMatch;

typedef struct nuc_Rule {
    int32_t kind;
    struct nuc_Node* /* nullable */ pat;
    struct nuc_Node* /* nullable */ tmpl;
    struct nuc_StrView reason;
    struct nuc_StrView flag;
    int32_t lines;
    struct nuc_Node* /* nullable */ names;
    bool (*guard)(struct nuc_RwMatch*);
    void (*emit)(struct nuc_RwMatch*);
    size_t hits;
    size_t refused;
} nuc_Rule;

#ifndef NUC_INST_nuc_Vector_nuc_Rule
#define NUC_INST_nuc_Vector_nuc_Rule
typedef struct nuc_Vector_nuc_Rule {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_Rule;
#endif

typedef struct nuc_Rules {
    struct nuc_StrView name;
    struct nuc_Vector_nuc_Rule rules;
} nuc_Rules;

struct nuc_Rules* nuc_rw_rules_new(struct nuc_StrView name) asm("nuc_rw-rules-new");
void nuc_rw_add(struct nuc_Rules* rs, int32_t kind, struct nuc_Node* /* nullable */ pat, struct nuc_Node* /* nullable */ tmpl, struct nuc_StrView reason, struct nuc_StrView flag, int32_t lines, struct nuc_Node* /* nullable */ names, bool (*guard)(struct nuc_RwMatch*), void (*emit)(struct nuc_RwMatch*)) asm("nuc_rw-add");
struct nuc_Node* /* nullable */ nuc_rw_wrapped(struct nuc_Node* /* nullable */ p, struct nuc_StrView head) asm("nuc_rw-wrapped");
int32_t nuc_rw_name_index(struct nuc_Node* /* nullable */ names, struct nuc_Node* /* nullable */ x) asm("nuc_rw-name-index");
void nuc_rw_bind(struct nuc_RwMatch* m, struct nuc_Node* /* nullable */ name, struct nuc_RwHole h) asm("nuc_rw-bind");
struct nuc_Syn* /* nullable */ nuc_rw_kid(struct nuc_Syn* /* nullable */ s, int32_t i) asm("nuc_rw-kid");
bool nuc_rw_match(struct nuc_RwMatch* m, struct nuc_Node* /* nullable */ p, struct nuc_Node* /* nullable */ n, struct nuc_Syn* /* nullable */ s) asm("nuc_rw-match");
struct nuc_Node* /* nullable */ nuc_rw_unspanned(struct nuc_RwMatch* m) asm("nuc_rw-unspanned");
struct nuc_Syn* nuc_rw_hole(struct nuc_RwMatch* m, int32_t i) asm("nuc_rw-hole");
#ifndef NUC_INST_nuc_Vector_pnuc_Syn
#define NUC_INST_nuc_Vector_pnuc_Syn
typedef struct nuc_Vector_pnuc_Syn {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_pnuc_Syn;
#endif

struct nuc_Vector_pnuc_Syn* nuc_rw_splice(struct nuc_RwMatch* m, int32_t i) asm("nuc_rw-splice");
struct nuc_Syn* nuc_rw_self(struct nuc_RwMatch* m) asm("nuc_rw-self");
typedef struct nuc_RwReport {
    size_t start;
    int32_t line;
    int32_t col;
    int32_t rule;
    bool flagged;
    struct nuc_StrView reason;
} nuc_RwReport;

#ifndef NUC_INST_nuc_Vector_nuc_RMacro
#define NUC_INST_nuc_Vector_nuc_RMacro
typedef struct nuc_Vector_nuc_RMacro {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_RMacro;
#endif

#ifndef NUC_INST_nuc_Vector_nuc_RwReport
#define NUC_INST_nuc_Vector_nuc_RwReport
typedef struct nuc_Vector_nuc_RwReport {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_RwReport;
#endif

typedef struct nuc_Rewriter {
    struct nuc_StrView src;
    struct nuc_SynFile* /* nullable */ file;
    struct nuc_Edits* /* nullable */ edits;
    struct nuc_Vector_nuc_RMacro* table;
    struct nuc_Rules* rules;
    struct nuc_Vector_nuc_RwReport* reports;
    size_t rewrites;
    bool in_strings;
    int32_t depth;
    size_t strings;
    size_t fragments;
    size_t skipped;
    bool carry;
} nuc_Rewriter;

extern struct nuc_Rewriter* /* nullable */ nuc_g_rw asm("nuc_g-rw");
struct nuc_Rewriter* nuc_rw_cur(void) asm("nuc_rw-cur");
int32_t nuc_rw_column(struct nuc_StrView text, size_t at, int32_t base) asm("nuc_rw-column");
int32_t nuc_rw_col(struct nuc_RwMatch* out) asm("nuc_rw-col");
int32_t nuc_rw_form_col(struct nuc_RwMatch* out) asm("nuc_rw-form-col");
void nuc_rw_put(struct nuc_RwMatch* out, struct nuc_StrView text) asm("nuc_rw-put");
void nuc_rw_refuse_text(struct nuc_RwMatch* out, struct nuc_StrView why) asm("nuc_rw-refuse-text");
void nuc_rw_put_gap(struct nuc_RwMatch* out, size_t from, size_t to, int32_t indent) asm("nuc_rw-put-gap");
bool nuc_rw_in_string_QMARK(struct nuc_Syn* s, size_t at) asm("nuc_rw-in-string_QMARK");
void nuc_rw_put_shifted(struct nuc_RwMatch* out, struct nuc_StrView text, int32_t delta) asm("nuc_rw-put-shifted");
bool nuc_rw_in_file_string_QMARK(struct nuc_SynFile* f, size_t at) asm("nuc_rw-in-file-string_QMARK");
bool nuc_rw_multiline_QMARK(struct nuc_StrView v) asm("nuc_rw-multiline_QMARK");
void nuc_rw_put_range(struct nuc_RwMatch* out, size_t start, size_t end) asm("nuc_rw-put-range");
void nuc_rw_put_syn(struct nuc_RwMatch* out, struct nuc_Syn* s) asm("nuc_rw-put-syn");
bool nuc_rw_splice_empty_QMARK(struct nuc_RwHole h) asm("nuc_rw-splice-empty_QMARK");
void nuc_rw_put_splice(struct nuc_RwMatch* out, struct nuc_RwHole h) asm("nuc_rw-put-splice");
struct nuc_RwHole nuc_rw_hole_of(struct nuc_RwMatch* out, struct nuc_Node* /* nullable */ name) asm("nuc_rw-hole-of");
bool nuc_rw_has_hole_QMARK(struct nuc_Node* /* nullable */ t, int32_t level) asm("nuc_rw-has-hole_QMARK");
int32_t nuc_rw_elem_level(struct nuc_Node* /* nullable */ t, int32_t i, int32_t level) asm("nuc_rw-elem-level");
void nuc_rw_put_node(struct nuc_RwMatch* out, struct nuc_Node* /* nullable */ t, int32_t level) asm("nuc_rw-put-node");
bool nuc_rw_prefix_reads_back_QMARK(struct nuc_RwMatch* out, size_t mark, size_t inner, struct nuc_Node* /* nullable */ t) asm("nuc_rw-prefix-reads-back_QMARK");
struct nuc_StrView nuc_src_text(struct nuc_Syn* s) asm("nuc_src-text");
bool nuc_same_text_QMARK(struct nuc_Syn* a, struct nuc_Syn* b) asm("nuc_same-text_QMARK");
struct nuc_StrView nuc_src_slice(size_t start, size_t end) asm("nuc_src-slice");
bool nuc_in_string_QMARK(struct nuc_Syn* s) asm("nuc_in-string_QMARK");
bool nuc_prefix_form_QMARK(struct nuc_Syn* s) asm("nuc_prefix-form_QMARK");
bool nuc_spelled_QMARK(struct nuc_Syn* s, struct nuc_StrView prefix);
bool nuc_has_comment_QMARK(struct nuc_Syn* s) asm("nuc_has-comment_QMARK");
bool nuc_has_discard_QMARK(struct nuc_Syn* s) asm("nuc_has-discard_QMARK");
bool nuc_operand_of_QMARK(struct nuc_Syn* s, struct nuc_Node* head, int32_t i) asm("nuc_operand-of_QMARK");
int32_t nuc_slot_kind(struct nuc_Syn* s) asm("nuc_slot-kind");
int32_t nuc_rw_slot_path(int32_t own, struct nuc_Node* /* nullable */ n, struct nuc_Node* /* nullable */ target) asm("nuc_rw-slot-path");
struct nuc_StrView nuc_rw_wrapper(struct nuc_Syn* p, struct nuc_Syn* k) asm("nuc_rw-wrapper");
int32_t nuc_rw_qq_level(struct nuc_Syn* s) asm("nuc_rw-qq-level");
bool nuc_rw_under_QMARK(struct nuc_Syn* s, struct nuc_StrView head) asm("nuc_rw-under_QMARK");
bool nuc_in_quote_QMARK(struct nuc_Syn* s) asm("nuc_in-quote_QMARK");
bool nuc_in_quasiquote_QMARK(struct nuc_Syn* s) asm("nuc_in-quasiquote_QMARK");
bool nuc_in_unquote_QMARK(struct nuc_Syn* s) asm("nuc_in-unquote_QMARK");
void nuc_rw_report(struct nuc_Rewriter* rw, struct nuc_Syn* s, size_t rule, bool flagged, struct nuc_StrView why) asm("nuc_rw-report");
struct nuc_Vector_nuc_Edit* nuc_edits_outermost(struct nuc_Edits* e) asm("nuc_edits-outermost");
bool nuc_rw_map_edits(struct nuc_Edits* e, struct nuc_Edits* ie, struct nuc_StrSource* ss) asm("nuc_rw-map-edits");
struct nuc_RwReport nuc_rw_map_report(struct nuc_Rewriter* rw, struct nuc_Syn* s, struct nuc_StrSource* ss, struct nuc_RwReport p) asm("nuc_rw-map-report");
void nuc_rw_string(struct nuc_Rewriter* rw, struct nuc_Syn* s) asm("nuc_rw-string");
void nuc_rw_string_source(struct nuc_Rewriter* rw, struct nuc_Syn* s, struct nuc_StrSource* ss, bool carry) asm("nuc_rw-string-source");
bool nuc_edits_check_outermost(struct nuc_StrView src, struct nuc_Edits* e) asm("nuc_edits-check-outermost");
void nuc_rw_refuse(struct nuc_Rewriter* rw, struct nuc_Syn* s, size_t j, struct nuc_StrView why) asm("nuc_rw-refuse");
void nuc_rw_match_reset(struct nuc_RwMatch* m, struct nuc_Syn* s, struct nuc_Rule* r, struct nuc_StrView src) asm("nuc_rw-match-reset");
bool nuc_rw_drops_QMARK(struct nuc_RwMatch* m, struct nuc_Syn* s, struct nuc_Vector_nuc_SynSpan* spans) asm("nuc_rw-drops_QMARK");
bool nuc_rw_try(struct nuc_Rewriter* rw, struct nuc_RwMatch* m, struct nuc_Syn* s, size_t j) asm("nuc_rw-try");
void nuc_rw_visit_kids(struct nuc_Rewriter* rw, struct nuc_RwMatch* m, struct nuc_Vector_pnuc_Syn* ks) asm("nuc_rw-visit-kids");
void nuc_rw_visit(struct nuc_Rewriter* rw, struct nuc_RwMatch* m, struct nuc_Syn* s) asm("nuc_rw-visit");
void nuc_rw_sort_reports(struct nuc_Vector_nuc_RwReport* v) asm("nuc_rw-sort-reports");
typedef struct nuc_Rewrite {
    struct nuc_String text;
    struct nuc_Vector_nuc_RwReport* reports;
    size_t rewrites;
    size_t strings;
    size_t fragments;
    size_t skipped;
} nuc_Rewrite;

void nuc_drop_pnuc_Rewrite(struct nuc_Rewrite* self) asm("nuc_drop.pnuc_Rewrite");
typedef struct nuc_RewriteResult {
    int32_t tag;
    union {
        struct nuc_Rewrite ok;
        struct nuc_ReadError err;
    } payload;
} nuc_RewriteResult;

enum nuc_RewriteResult_tag {
    nuc_RewriteResult_ok = 0,
    nuc_RewriteResult_err = 1
};

void nuc_rw_init(struct nuc_Rewriter* rw, struct nuc_StrView src, struct nuc_SynFile* f, struct nuc_Edits* e, struct nuc_Rules* rules, struct nuc_Vector_nuc_RwReport* reports, bool in_strings, int32_t depth) asm("nuc_rw-init");
void nuc_rw_run_pass(struct nuc_Rewriter* rw) asm("nuc_rw-run-pass");
struct nuc_RewriteResult nuc_rewrite_source(struct nuc_Rules* rules, struct nuc_StrView src) asm("nuc_rewrite-source");
struct nuc_RewriteResult nuc_rewrite_source_in_strings(struct nuc_Rules* rules, struct nuc_StrView src) asm("nuc_rewrite-source-in-strings");
struct nuc_RewriteResult nuc_rw_rewrite(struct nuc_Rules* rules, struct nuc_StrView src, bool in_strings) asm("nuc_rw-rewrite");
typedef struct nuc_RwRun {
    bool apply;
    bool in_strings;
    size_t files;
    size_t changed;
    size_t rewrites;
    size_t reported;
    size_t failed;
    size_t unread;
    size_t strings;
    size_t fragments;
    size_t skipped;
} nuc_RwRun;

/* rw-read-file: uses an error-union or option type; not exported */
/* rw-write-file: uses an error-union or option type; not exported */
void nuc_rw_run_file(struct nuc_Rules* rules, struct nuc_RwRun* run, struct nuc_StrView path) asm("nuc_rw-run-file");
void nuc_rw_run_arg(struct nuc_Rules* rules, struct nuc_RwRun* run, struct nuc_StrView a) asm("nuc_rw-run-arg");
struct nuc_StrView nuc_rw_arg(void* argv, int32_t i) asm("nuc_rw-arg");
int32_t nuc_refactor_main(int32_t argc, void* argv, struct nuc_Rules* rules) asm("nuc_refactor-main");
typedef struct nuc_RwForm {
    struct nuc_Node* /* nullable */ bad;
    struct nuc_StrView msg;
    int32_t kind;
    struct nuc_Node* /* nullable */ pat;
    struct nuc_Node* /* nullable */ tmpl;
    struct nuc_Node* /* nullable */ reason;
    struct nuc_Node* /* nullable */ flag;
    int32_t lines;
    struct nuc_Node* names;
    struct nuc_Node* splices;
    struct nuc_Node* /* nullable */ guard;
    struct nuc_Node* /* nullable */ emit;
} nuc_RwForm;

void nuc_rw_form_fail(struct nuc_RwForm* f, struct nuc_Node* /* nullable */ at, struct nuc_String msg) asm("nuc_rw-form-fail");
bool nuc_rw_sym_is_QMARK(struct nuc_Node* /* nullable */ n, int32_t kind, struct nuc_StrView name) asm("nuc_rw-sym-is_QMARK");
struct nuc_StrView nuc_rw_sym_text(struct nuc_Node* /* nullable */ n) asm("nuc_rw-sym-text");
struct nuc_Node* nuc_rw_str_node(struct nuc_Symbol s) asm("nuc_rw-str-node");
bool nuc_rw_form_splice_QMARK(struct nuc_RwForm* f, struct nuc_Node* /* nullable */ h) asm("nuc_rw-form-splice_QMARK");
void nuc_rw_pat_holes(struct nuc_RwForm* f, struct nuc_Node* at, struct nuc_Node* /* nullable */ p, bool last) asm("nuc_rw-pat-holes");
void nuc_rw_tmpl_check(struct nuc_RwForm* f, struct nuc_Node* at, struct nuc_Node* /* nullable */ t, int32_t level, bool in_list) asm("nuc_rw-tmpl-check");
struct nuc_RwForm* nuc_rw_parse_rule(struct nuc_Node* r) asm("nuc_rw-parse-rule");
