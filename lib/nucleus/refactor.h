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
#define REPORT_VERSION 4
typedef struct nuc_RRef {
    struct nuc_StrView file;
    int64_t start;
    int64_t end;
    struct nuc_StrView name;
    struct nuc_StrView role;
    struct nuc_StrView kind;
    struct nuc_StrView tfile;
    int64_t tstart;
    int64_t tend;
    struct nuc_StrView tkey;
    struct nuc_StrView why;
    struct nuc_StrView macro;
    int64_t cstart;
    int64_t cend;
    int64_t cline;
    int64_t ccol;
    struct nuc_StrView via;
} nuc_RRef;

typedef struct nuc_RDef {
    struct nuc_StrView file;
    int64_t start;
    int64_t end;
    struct nuc_StrView name;
    struct nuc_StrView ns;
    struct nuc_StrView key;
    struct nuc_StrView kind;
    struct nuc_StrView form;
    struct nuc_StrView link;
    struct nuc_StrView macro;
    bool private_;
    bool host;
} nuc_RDef;

#ifndef NUC_INST_nuc_Vector_nuc_StrView
#define NUC_INST_nuc_Vector_nuc_StrView
typedef struct nuc_Vector_nuc_StrView {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_StrView;
#endif

#ifndef NUC_INST_nuc_Vector_nuc_RDef
#define NUC_INST_nuc_Vector_nuc_RDef
typedef struct nuc_Vector_nuc_RDef {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_RDef;
#endif

#ifndef NUC_INST_nuc_Vector_nuc_RRef
#define NUC_INST_nuc_Vector_nuc_RRef
typedef struct nuc_Vector_nuc_RRef {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_RRef;
#endif

#ifndef NUC_INST_nuc_HashMap_nuc_Symbol_i64
#define NUC_INST_nuc_HashMap_nuc_Symbol_i64
typedef struct nuc_HashMap_nuc_Symbol_i64 {
    uint8_t* keys;
    uint8_t* vals;
    uint8_t* states;
    size_t count;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_HashMap_nuc_Symbol_i64;
#endif

#ifndef NUC_INST_nuc_HashMap_nuc_Symbol_pnuc_Vector_usize
#define NUC_INST_nuc_HashMap_nuc_Symbol_pnuc_Vector_usize
typedef struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize {
    uint8_t* keys;
    uint8_t* vals;
    uint8_t* states;
    size_t count;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_HashMap_nuc_Symbol_pnuc_Vector_usize;
#endif

#ifndef NUC_INST_nuc_HashMap_nuc_Symbol_usize
#define NUC_INST_nuc_HashMap_nuc_Symbol_usize
typedef struct nuc_HashMap_nuc_Symbol_usize {
    uint8_t* keys;
    uint8_t* vals;
    uint8_t* states;
    size_t count;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_HashMap_nuc_Symbol_usize;
#endif

typedef struct nuc_Report {
    struct nuc_StrView unit;
    struct nuc_Vector_nuc_StrView files;
    struct nuc_Vector_nuc_RDef defs;
    struct nuc_Vector_nuc_RRef refs;
    struct nuc_HashMap_nuc_Symbol_i64 spans;
    struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize targets;
    struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize calls;
    struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize loose;
    struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize by_file;
    struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize defs_by_file;
    struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize calls_by_file;
    struct nuc_HashMap_nuc_Symbol_usize def_names;
    struct nuc_HashMap_nuc_Symbol_usize macros;
} nuc_Report;

typedef struct nuc_ReportResult {
    int32_t tag;
    union {
        struct nuc_Report* ok;
        struct nuc_StrView err;
    } payload;
} nuc_ReportResult;

enum nuc_ReportResult_tag {
    nuc_ReportResult_ok = 0,
    nuc_ReportResult_err = 1
};

struct nuc_StrView nuc_rp_text(struct nuc_Node* /* nullable */ m, struct nuc_StrView k) asm("nuc_rp-text");
int64_t nuc_rp_int(struct nuc_Node* /* nullable */ m, struct nuc_StrView k) asm("nuc_rp-int");
bool nuc_rp_bool(struct nuc_Node* /* nullable */ m, struct nuc_StrView k) asm("nuc_rp-bool");
struct nuc_Symbol nuc_rp_key(struct nuc_StrView path, int64_t start, int64_t end) asm("nuc_rp-key");
struct nuc_StrView nuc_rp_arena_text(struct nuc_String s) asm("nuc_rp-arena-text");
void nuc_rp_push(struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize* m, struct nuc_Symbol k, size_t i) asm("nuc_rp-push");
#ifndef NUC_INST_nuc_Vector_usize
#define NUC_INST_nuc_Vector_usize
typedef struct nuc_Vector_usize {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_usize;
#endif

struct nuc_Vector_usize* /* nullable */ nuc_rp_list(struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize* m, struct nuc_Symbol k) asm("nuc_rp-list");
struct nuc_RRef nuc_rp_ref(struct nuc_Node* /* nullable */ m) asm("nuc_rp-ref");
void nuc_rp_add_ref(struct nuc_Report* r, struct nuc_Node* /* nullable */ m) asm("nuc_rp-add-ref");
void nuc_rp_add_def(struct nuc_Report* r, struct nuc_Node* /* nullable */ m) asm("nuc_rp-add-def");
struct nuc_Report* nuc_report_new(void) asm("nuc_report-new");
bool nuc_rp_skip_QMARK(struct nuc_StrView line, struct nuc_Vector_nuc_StrView* needles) asm("nuc_rp-skip_QMARK");
struct nuc_ReportResult nuc_report_parse(struct nuc_StrView text) asm("nuc_report-parse");
struct nuc_ReportResult nuc_report_parse_for(struct nuc_StrView text, struct nuc_Vector_nuc_StrView* only) asm("nuc_report-parse-for");
struct nuc_ReportResult nuc_report_run(struct nuc_StrView compiler, struct nuc_StrView root, struct nuc_Vector_nuc_StrView* only) asm("nuc_report-run");
bool nuc_report_reads_QMARK(struct nuc_Report* r, struct nuc_StrView path) asm("nuc_report-reads_QMARK");
typedef struct nuc_RnFile {
    struct nuc_StrView path;
    struct nuc_StrView src;
    struct nuc_SynFile* syn;
    struct nuc_Vector_usize strays;
} nuc_RnFile;

#ifndef NUC_INST_nuc_HashMap_nuc_Symbol_pnuc_RnFile
#define NUC_INST_nuc_HashMap_nuc_Symbol_pnuc_RnFile
typedef struct nuc_HashMap_nuc_Symbol_pnuc_RnFile {
    uint8_t* keys;
    uint8_t* vals;
    uint8_t* states;
    size_t count;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_HashMap_nuc_Symbol_pnuc_RnFile;
#endif

#ifndef NUC_INST_nuc_HashMap_nuc_Symbol_pnuc_HashMap_nuc_Symbol_i64
#define NUC_INST_nuc_HashMap_nuc_Symbol_pnuc_HashMap_nuc_Symbol_i64
typedef struct nuc_HashMap_nuc_Symbol_pnuc_HashMap_nuc_Symbol_i64 {
    uint8_t* keys;
    uint8_t* vals;
    uint8_t* states;
    size_t count;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_HashMap_nuc_Symbol_pnuc_HashMap_nuc_Symbol_i64;
#endif

typedef struct nuc_RnCtx {
    struct nuc_Report* rep;
    bool in_strings;
    struct nuc_HashMap_nuc_Symbol_pnuc_RnFile files;
    struct nuc_HashMap_nuc_Symbol_pnuc_HashMap_nuc_Symbol_i64 spelled;
} nuc_RnCtx;

struct nuc_RnCtx* nuc_rename_ctx_new(struct nuc_Report* rep, bool in_strings) asm("nuc_rename-ctx-new");
typedef struct nuc_Refusal {
    size_t at;
    struct nuc_StrView reason;
} nuc_Refusal;

typedef struct nuc_RnPlan {
    struct nuc_StrView path;
    struct nuc_StrView old;
    struct nuc_StrView new_;
    struct nuc_SynSpan binder;
    struct nuc_Vector_nuc_SynSpan sites;
    struct nuc_Refusal refusal;
} nuc_RnPlan;

bool nuc_rn_plan_ok_QMARK(struct nuc_RnPlan* p) asm("nuc_rn-plan-ok_QMARK");
struct nuc_Syn* /* nullable */ nuc_rn_kid_holding(struct nuc_Vector_pnuc_Syn* ks, size_t start, size_t end) asm("nuc_rn-kid-holding");
struct nuc_Syn* /* nullable */ nuc_rn_syn_at(struct nuc_SynFile* f, size_t start, size_t end) asm("nuc_rn-syn-at");
struct nuc_StrView nuc_rn_src_at(struct nuc_RnFile* f, int64_t start, int64_t end) asm("nuc_rn-src-at");
struct nuc_Vector_usize* nuc_rn_in_file(struct nuc_Report* rep, struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize* m, struct nuc_StrView path) asm("nuc_rn-in-file");
struct nuc_Refusal nuc_rn_file_load(struct nuc_RnCtx* ctx, struct nuc_StrView path, struct nuc_StrView src) asm("nuc_rn-file-load");
struct nuc_RnFile* /* nullable */ nuc_rn_file(struct nuc_RnCtx* ctx, struct nuc_StrView path) asm("nuc_rn-file");
struct nuc_RnFile* /* nullable */ nuc_rn_file_or_read(struct nuc_RnCtx* ctx, struct nuc_StrView path) asm("nuc_rn-file-or-read");
#ifndef NUC_INST_nuc_Vector_nuc_Symbol
#define NUC_INST_nuc_Vector_nuc_Symbol
typedef struct nuc_Vector_nuc_Symbol {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_Symbol;
#endif

typedef struct nuc_RnScan {
    struct nuc_RnCtx* ctx;
    struct nuc_RnFile* f;
    struct nuc_StrView old;
    struct nuc_StrView new_;
    struct nuc_Syn* region;
    struct nuc_Refusal refusal;
    struct nuc_Vector_nuc_Symbol macros;
    struct nuc_Vector_usize macro_at;
} nuc_RnScan;

void nuc_rn_refuse(struct nuc_RnScan* sc, size_t at, struct nuc_StrView why) asm("nuc_rn-refuse");
bool nuc_rn_refused_QMARK(struct nuc_RnScan* sc) asm("nuc_rn-refused_QMARK");
struct nuc_RRef nuc_rn_rec(struct nuc_RnScan* sc, size_t i) asm("nuc_rn-rec");
bool nuc_rn_boundary_QMARK(int32_t c) asm("nuc_rn-boundary_QMARK");
bool nuc_rn_token_in_QMARK(struct nuc_StrView t, struct nuc_StrView name) asm("nuc_rn-token-in_QMARK");
bool nuc_rn_spellable_QMARK(struct nuc_StrView t) asm("nuc_rn-spellable_QMARK");
bool nuc_rn_spells_QMARK(struct nuc_StrView t, struct nuc_StrView name) asm("nuc_rn-spells_QMARK");
void nuc_rn_check_old(struct nuc_RnScan* sc, size_t b, size_t e) asm("nuc_rn-check-old");
void nuc_rn_scan_atom(struct nuc_RnScan* sc, struct nuc_Syn* s, bool in_macro) asm("nuc_rn-scan-atom");
void nuc_rn_scan_string(struct nuc_RnScan* sc, struct nuc_Syn* s, bool in_macro) asm("nuc_rn-scan-string");
void nuc_rn_note_macro(struct nuc_RnScan* sc, struct nuc_StrView key, size_t at) asm("nuc_rn-note-macro");
void nuc_rn_scan_calls(struct nuc_RnScan* sc, struct nuc_Syn* s) asm("nuc_rn-scan-calls");
void nuc_rn_scan_call_rec(struct nuc_RnScan* sc, struct nuc_RRef x, size_t at) asm("nuc_rn-scan-call-rec");
bool nuc_rn_unbound_local_QMARK(struct nuc_RRef x) asm("nuc_rn-unbound-local_QMARK");
bool nuc_rn_macro_call_QMARK(struct nuc_RnScan* sc, struct nuc_Syn* s) asm("nuc_rn-macro-call_QMARK");
void nuc_rn_scan(struct nuc_RnScan* sc, struct nuc_Syn* s, bool in_macro) asm("nuc_rn-scan");
bool nuc_rn_code_slot_QMARK(int32_t k) asm("nuc_rn-code-slot_QMARK");
struct nuc_Syn* nuc_rn_region(struct nuc_Syn* a) asm("nuc_rn-region");
void nuc_rn_spellings_of(struct nuc_RnFile* f, struct nuc_Syn* s, struct nuc_HashMap_nuc_Symbol_i64* out) asm("nuc_rn-spellings-of");
int32_t nuc_rn_macro_spells(struct nuc_RnCtx* ctx, struct nuc_Symbol key, struct nuc_StrView name) asm("nuc_rn-macro-spells");
bool nuc_rn_ident_text_QMARK(struct nuc_StrView t) asm("nuc_rn-ident-text_QMARK");
struct nuc_StrView nuc_rn_bad_name(struct nuc_StrView t) asm("nuc_rn-bad-name");
bool nuc_rn_builtin_type_QMARK(struct nuc_StrView t) asm("nuc_rn-builtin-type_QMARK");
struct nuc_RnPlan* nuc_rn_fail(struct nuc_RnPlan* p, size_t at, struct nuc_StrView why) asm("nuc_rn-fail");
struct nuc_RnPlan* nuc_rename_local_plan(struct nuc_RnCtx* ctx, struct nuc_StrView path, size_t at, struct nuc_StrView new_) asm("nuc_rename-local-plan");
struct nuc_RnPlan* nuc_rn_plan_binder(struct nuc_RnCtx* ctx, struct nuc_RnFile* f, struct nuc_RnPlan* p, size_t bs, size_t be) asm("nuc_rn-plan-binder");
void nuc_rn_check_sites(struct nuc_RnScan* sc, struct nuc_RnPlan* p, struct nuc_Symbol bkey) asm("nuc_rn-check-sites");
void nuc_rn_check_outer(struct nuc_RnScan* sc, size_t bs, size_t be) asm("nuc_rn-check-outer");
void nuc_rn_check_loose(struct nuc_RnScan* sc) asm("nuc_rn-check-loose");
void nuc_rn_check_strays(struct nuc_RnScan* sc) asm("nuc_rn-check-strays");
void nuc_rn_check_discards(struct nuc_RnScan* sc) asm("nuc_rn-check-discards");
bool nuc_rn_enclosed_by_macro_QMARK(struct nuc_RnScan* sc, struct nuc_Syn* rg) asm("nuc_rn-enclosed-by-macro_QMARK");
void nuc_rn_check_macros(struct nuc_RnScan* sc) asm("nuc_rn-check-macros");
typedef struct nuc_RenameResult {
    int32_t tag;
    union {
        struct nuc_String ok;
        struct nuc_Refusal err;
    } payload;
} nuc_RenameResult;

enum nuc_RenameResult_tag {
    nuc_RenameResult_ok = 0,
    nuc_RenameResult_err = 1
};

void nuc_rename_edits_add(struct nuc_Edits* e, struct nuc_RnPlan* p) asm("nuc_rename-edits-add");
struct nuc_RenameResult nuc_rename_edits_apply(struct nuc_StrView src, struct nuc_Edits* e, size_t at) asm("nuc_rename-edits-apply");
struct nuc_RenameResult nuc_rename_local_apply(struct nuc_StrView src, struct nuc_RnPlan* p) asm("nuc_rename-local-apply");
struct nuc_Refusal nuc_rename_file_load(struct nuc_RnCtx* ctx, struct nuc_StrView path, struct nuc_StrView src) asm("nuc_rename-file-load");
struct nuc_RenameResult nuc_rename_local(struct nuc_RnCtx* ctx, struct nuc_StrView path, struct nuc_StrView src, size_t at, struct nuc_StrView new_) asm("nuc_rename-local");
int64_t nuc_rn_offset(struct nuc_StrView src, int64_t line, int64_t col) asm("nuc_rn-offset");
int64_t nuc_rn_line(struct nuc_StrView src, size_t at) asm("nuc_rn-line");
void nuc_rn_print_site(struct nuc_StrView path, struct nuc_StrView src, size_t at, struct nuc_StrView what) asm("nuc_rn-print-site");
int64_t nuc_rn_digits(struct nuc_StrView t) asm("nuc_rn-digits");
int32_t nuc_rn_usage(void) asm("nuc_rn-usage");
int32_t nuc_rename_local_main(int32_t argc, void* argv) asm("nuc_rename-local-main");
int32_t nuc_rn_main(struct nuc_StrView path, int64_t line, int64_t col, struct nuc_StrView new_, bool apply, bool in_strings, struct nuc_StrView root, struct nuc_StrView report, struct nuc_StrView compiler) asm("nuc_rn-main");
int32_t nuc_rn_main_with(struct nuc_StrView path, struct nuc_StrView src, int64_t line, int64_t col, struct nuc_StrView new_, bool apply, bool in_strings, struct nuc_ReportResult res) asm("nuc_rn-main-with");
enum RgWhat {
    RgWhat_RG_ATOM = 0,
    RgWhat_RG_DATA = 1,
    RgWhat_RG_LIST = 2
};

typedef struct nuc_RgOcc {
    struct nuc_StrView path;
    size_t b;
    size_t e;
    size_t q;
    int32_t what;
    struct nuc_Syn* syn;
} nuc_RgOcc;

typedef struct nuc_RgText {
    struct nuc_StrView path;
    size_t at;
    struct nuc_StrView text;
} nuc_RgText;

typedef struct nuc_RgOpts {
    struct nuc_StrView compiler;
    struct nuc_StrView compiler_src;
    bool ir_check;
    struct nuc_Vector_nuc_StrView edit;
} nuc_RgOpts;

#ifndef NUC_INST_nuc_HashMap_nuc_Symbol_pnuc_Vector_nuc_RgOcc
#define NUC_INST_nuc_HashMap_nuc_Symbol_pnuc_Vector_nuc_RgOcc
typedef struct nuc_HashMap_nuc_Symbol_pnuc_Vector_nuc_RgOcc {
    uint8_t* keys;
    uint8_t* vals;
    uint8_t* states;
    size_t count;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_HashMap_nuc_Symbol_pnuc_Vector_nuc_RgOcc;
#endif

#ifndef NUC_INST_nuc_Vector_nuc_RgText
#define NUC_INST_nuc_Vector_nuc_RgText
typedef struct nuc_Vector_nuc_RgText {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_RgText;
#endif

typedef struct nuc_RgRoot {
    struct nuc_StrView name;
    struct nuc_RnCtx* ctx;
    struct nuc_HashMap_nuc_Symbol_pnuc_Vector_nuc_RgOcc occ;
    struct nuc_Vector_nuc_RgText texts;
    struct nuc_HashMap_nuc_Symbol_usize def_spans;
    struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize key_refs;
    struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize key_defs;
    struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize loose;
    struct nuc_HashMap_nuc_Symbol_usize links;
    size_t nfiles;
    struct nuc_StrView ir;
    bool ir_read;
    struct nuc_Refusal refusal;
    struct nuc_StrView refused;
} nuc_RgRoot;

struct nuc_StrView nuc_rg_bare(struct nuc_StrView name) asm("nuc_rg-bare");
struct nuc_StrView nuc_rg_template_key(struct nuc_StrView key) asm("nuc_rg-template-key");
struct nuc_StrView nuc_rg_ir_token(struct nuc_StrView name) asm("nuc_rg-ir-token");
struct nuc_StrView nuc_rg_ir_sanitize(struct nuc_StrView name) asm("nuc_rg-ir-sanitize");
struct nuc_Vector_nuc_StrView* nuc_rg_link_spellings(struct nuc_StrView name) asm("nuc_rg-link-spellings");
void nuc_rg_push_occ(struct nuc_HashMap_nuc_Symbol_pnuc_Vector_nuc_RgOcc* m, struct nuc_Symbol k, struct nuc_RgOcc o) asm("nuc_rg-push-occ");
#ifndef NUC_INST_nuc_Vector_nuc_RgOcc
#define NUC_INST_nuc_Vector_nuc_RgOcc
typedef struct nuc_Vector_nuc_RgOcc {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_RgOcc;
#endif

struct nuc_Vector_nuc_RgOcc* /* nullable */ nuc_rg_occ(struct nuc_RgRoot* r, struct nuc_StrView name) asm("nuc_rg-occ");
struct nuc_StrView nuc_rg_head_text(struct nuc_RnFile* f, struct nuc_Syn* s) asm("nuc_rg-head-text");
int64_t nuc_rg_list_from(struct nuc_RnFile* f, struct nuc_Syn* s) asm("nuc_rg-list-from");
bool nuc_rg_type_keyword_QMARK(struct nuc_Syn* s) asm("nuc_rg-type-keyword_QMARK");
void nuc_rg_index_atom(struct nuc_RgRoot* r, struct nuc_RnFile* f, struct nuc_Syn* s, bool in_macro, bool list) asm("nuc_rg-index-atom");
void nuc_rg_index_spelling(struct nuc_RgRoot* r, struct nuc_RnFile* f, struct nuc_Syn* s, struct nuc_StrView t) asm("nuc_rg-index-spelling");
void nuc_rg_index_string(struct nuc_RgRoot* r, struct nuc_RnFile* f, struct nuc_Syn* s, bool data) asm("nuc_rg-index-string");
void nuc_rg_index(struct nuc_RgRoot* r, struct nuc_RnScan* sc, struct nuc_Syn* s, bool in_macro, bool in_def, bool list) asm("nuc_rg-index");
void nuc_rg_index_file(struct nuc_RgRoot* r, struct nuc_RnFile* f) asm("nuc_rg-index-file");
void nuc_rg_index_report(struct nuc_RgRoot* r) asm("nuc_rg-index-report");
struct nuc_RgRoot* nuc_rg_root_refuse(struct nuc_RgRoot* r, struct nuc_StrView path, size_t at, struct nuc_StrView why) asm("nuc_rg-root-refuse");
struct nuc_RgRoot* nuc_rename_global_root(struct nuc_StrView name, struct nuc_Report* rep, bool in_strings) asm("nuc_rename-global-root");
typedef struct nuc_RgSite {
    struct nuc_StrView path;
    size_t b;
    size_t e;
    size_t q;
    size_t qe;
} nuc_RgSite;

#ifndef NUC_INST_nuc_Vector_nuc_RgSite
#define NUC_INST_nuc_Vector_nuc_RgSite
typedef struct nuc_Vector_nuc_RgSite {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_RgSite;
#endif

typedef struct nuc_RgPlan {
    struct nuc_StrView old;
    struct nuc_StrView new_;
    struct nuc_StrView key;
    struct nuc_StrView kind;
    struct nuc_Vector_nuc_RgSite sites;
    struct nuc_Refusal refusal;
    struct nuc_StrView refused;
    struct nuc_Vector_nuc_StrView headers;
} nuc_RgPlan;

bool nuc_rg_plan_ok_QMARK(struct nuc_RgPlan* p) asm("nuc_rg-plan-ok_QMARK");
struct nuc_RgPlan* nuc_rg_fail(struct nuc_RgPlan* p, struct nuc_StrView path, size_t at, struct nuc_StrView why) asm("nuc_rg-fail");
struct nuc_RRef nuc_rg_ref(struct nuc_RgRoot* r, size_t i) asm("nuc_rg-ref");
struct nuc_RDef nuc_rg_def(struct nuc_RgRoot* r, size_t i) asm("nuc_rg-def");
struct nuc_Vector_usize* /* nullable */ nuc_rg_list(struct nuc_HashMap_nuc_Symbol_pnuc_Vector_usize* m, struct nuc_StrView k) asm("nuc_rg-list");
bool nuc_rg_edits_QMARK(struct nuc_StrView kind, struct nuc_StrView role, struct nuc_StrView rk) asm("nuc_rg-edits_QMARK");
bool nuc_rg_kind_in_scope_QMARK(struct nuc_StrView kind) asm("nuc_rg-kind-in-scope_QMARK");
bool nuc_rg_declaring_QMARK(struct nuc_StrView form) asm("nuc_rg-declaring_QMARK");
struct nuc_Syn* /* nullable */ nuc_rg_top_form(struct nuc_RgRoot* r, struct nuc_StrView path, size_t start, size_t end) asm("nuc_rg-top-form");
bool nuc_rg_in_definer_QMARK(struct nuc_RgRoot* r, struct nuc_StrView key, struct nuc_StrView path, int64_t cs, int64_t ce) asm("nuc_rg-in-definer_QMARK");
bool nuc_rg_has_site_in_QMARK(struct nuc_Vector_nuc_RgSite* sites, struct nuc_StrView path, size_t start, size_t end) asm("nuc_rg-has-site-in_QMARK");
bool nuc_rg_template_site_QMARK(struct nuc_RgRoot* r, struct nuc_StrView key, struct nuc_Vector_nuc_RgSite* sites) asm("nuc_rg-template-site_QMARK");
bool nuc_rg_positional_name_QMARK(struct nuc_RgOcc o) asm("nuc_rg-positional-name_QMARK");
void nuc_rg_check_occ(struct nuc_RgRoot* r, struct nuc_RgPlan* p, struct nuc_StrView key, struct nuc_StrView kind, struct nuc_StrView old, size_t len, struct nuc_RgOcc o, struct nuc_Vector_nuc_RgSite* out) asm("nuc_rg-check-occ");
bool nuc_rg_member_QMARK(struct nuc_RRef x) asm("nuc_rg-member_QMARK");
void nuc_rg_check_key_refs(struct nuc_RgRoot* r, struct nuc_RgPlan* p, struct nuc_StrView key, struct nuc_StrView old, struct nuc_StrView dkey, struct nuc_Vector_nuc_RgSite* out) asm("nuc_rg-check-key-refs");
void nuc_rg_check_loose_old(struct nuc_RgRoot* r, struct nuc_RgPlan* p, struct nuc_StrView key, struct nuc_StrView old) asm("nuc_rg-check-loose-old");
struct nuc_StrView nuc_rg_relink(struct nuc_StrView link, struct nuc_StrView old, struct nuc_StrView new_) asm("nuc_rg-relink");
struct nuc_StrView nuc_rg_relink_any(struct nuc_StrView link, struct nuc_StrView old, struct nuc_StrView new_) asm("nuc_rg-relink-any");
bool nuc_rg_ir_char_QMARK(int32_t c) asm("nuc_rg-ir-char_QMARK");
bool nuc_rg_ir_has_QMARK(struct nuc_StrView ir, struct nuc_StrView tok) asm("nuc_rg-ir-has_QMARK");
struct nuc_StrView nuc_rg_root_ir(struct nuc_RgRoot* r, struct nuc_RgOpts* opts) asm("nuc_rg-root-ir");
void nuc_rg_check_new_name(struct nuc_RgRoot* r, struct nuc_RgPlan* p, struct nuc_StrView new_) asm("nuc_rg-check-new-name");
void nuc_rg_check_new(struct nuc_RgRoot* r, struct nuc_RgPlan* p, struct nuc_StrView key, struct nuc_RgOpts* opts) asm("nuc_rg-check-new");
extern struct nuc_HashMap_nuc_Symbol_i64* /* nullable */ nuc_g_rg_fixed asm("nuc_g-rg-fixed");
extern struct nuc_StrView nuc_g_rg_fixed_dir asm("nuc_g-rg-fixed-dir");
extern int64_t nuc_g_rg_fixed_files asm("nuc_g-rg-fixed-files");
struct nuc_HashMap_nuc_Symbol_i64* nuc_rg_fixed(void) asm("nuc_rg-fixed");
void nuc_rg_fixed_add(struct nuc_StrView t) asm("nuc_rg-fixed-add");
void nuc_rg_fixed_text(struct nuc_StrView t) asm("nuc_rg-fixed-text");
void nuc_rg_fixed_walk(struct nuc_SynFile* f, struct nuc_Syn* s) asm("nuc_rg-fixed-walk");
bool nuc_rg_fixed_load(struct nuc_StrView dir) asm("nuc_rg-fixed-load");
bool nuc_rg_core_ns_QMARK(struct nuc_StrView ns) asm("nuc_rg-core-ns_QMARK");
struct nuc_StrView nuc_rg_core_refusal(struct nuc_RDef d, struct nuc_RgOpts* opts) asm("nuc_rg-core-refusal");
struct nuc_StrView nuc_rg_key_at(struct nuc_RgRoot* r, struct nuc_RgPlan* p, struct nuc_StrView path, size_t at) asm("nuc_rg-key-at");
struct nuc_StrView nuc_rg_key_in(struct nuc_RgRoot* r, struct nuc_RgRoot* r0, struct nuc_StrView key0, struct nuc_Vector_usize* ds0, struct nuc_RgPlan* p) asm("nuc_rg-key-in");
void nuc_rg_root_sites(struct nuc_RgRoot* r, struct nuc_RgPlan* p, struct nuc_StrView key, struct nuc_StrView kind, struct nuc_RgOpts* opts, struct nuc_Vector_nuc_RgSite* out) asm("nuc_rg-root-sites");
struct nuc_StrView nuc_rg_old_bad(struct nuc_StrView old, struct nuc_StrView bad) asm("nuc_rg-old-bad");
void nuc_rg_check_name(struct nuc_RgRoot* r, struct nuc_RgPlan* p, struct nuc_StrView key, struct nuc_StrView kind, struct nuc_StrView old, struct nuc_StrView dkey, struct nuc_Vector_nuc_RgSite* out) asm("nuc_rg-check-name");
struct nuc_Vector_nuc_StrView* nuc_rg_union_arms(struct nuc_RgRoot* r, struct nuc_StrView key) asm("nuc_rg-union-arms");
bool nuc_rg_editable_QMARK(struct nuc_StrView path, struct nuc_RgOpts* opts) asm("nuc_rg-editable_QMARK");
struct nuc_StrView nuc_rg_sig(struct nuc_Vector_nuc_RgSite* sites, struct nuc_StrView path) asm("nuc_rg-sig");
struct nuc_RgPlan* nuc_rg_plan_new(struct nuc_StrView old, struct nuc_StrView new_) asm("nuc_rg-plan-new");
#ifndef NUC_INST_nuc_Vector_pnuc_RgRoot
#define NUC_INST_nuc_Vector_pnuc_RgRoot
typedef struct nuc_Vector_pnuc_RgRoot {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_pnuc_RgRoot;
#endif

struct nuc_RgPlan* nuc_rename_global_plan(struct nuc_Vector_pnuc_RgRoot* roots, struct nuc_StrView path, size_t at, struct nuc_StrView new_, struct nuc_RgOpts* opts) asm("nuc_rename-global-plan");
bool nuc_rg_seen_QMARK(struct nuc_HashMap_nuc_Symbol_i64* m, struct nuc_Symbol k) asm("nuc_rg-seen_QMARK");
#ifndef NUC_INST_nuc_Vector_pnuc_Vector_nuc_RgSite
#define NUC_INST_nuc_Vector_pnuc_Vector_nuc_RgSite
typedef struct nuc_Vector_pnuc_Vector_nuc_RgSite {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_pnuc_Vector_nuc_RgSite;
#endif

struct nuc_RgPlan* nuc_rg_merge(struct nuc_RgPlan* p, struct nuc_Vector_pnuc_RgRoot* roots, struct nuc_Vector_pnuc_Vector_nuc_RgSite* parts, struct nuc_RgOpts* opts) asm("nuc_rg-merge");
typedef struct nuc_RgOut {
    struct nuc_StrView path;
    struct nuc_StrView text;
} nuc_RgOut;

struct nuc_RnFile* /* nullable */ nuc_rg_src(struct nuc_Vector_pnuc_RgRoot* roots, struct nuc_StrView path) asm("nuc_rg-src");
#ifndef NUC_INST_nuc_Vector_nuc_RgOut
#define NUC_INST_nuc_Vector_nuc_RgOut
typedef struct nuc_Vector_nuc_RgOut {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_dynref_nucleus_allocator_Allocator alloc;
} nuc_Vector_nuc_RgOut;
#endif

struct nuc_Vector_nuc_RgOut* nuc_rename_global_apply(struct nuc_Vector_pnuc_RgRoot* roots, struct nuc_RgPlan* p) asm("nuc_rename-global-apply");
bool nuc_rg_c_char_QMARK(int32_t c) asm("nuc_rg-c-char_QMARK");
bool nuc_rg_c_has_QMARK(struct nuc_StrView text, struct nuc_StrView tok) asm("nuc_rg-c-has_QMARK");
bool nuc_rg_header_spells_QMARK(struct nuc_StrView h, struct nuc_StrView text, struct nuc_StrView old) asm("nuc_rg-header-spells_QMARK");
void nuc_rename_global_headers(struct nuc_RgPlan* p) asm("nuc_rename-global-headers");
void nuc_rg_print_site(struct nuc_StrView path, struct nuc_RnFile* /* nullable */ f, size_t at, struct nuc_StrView what) asm("nuc_rg-print-site");
int32_t nuc_rg_usage(void) asm("nuc_rg-usage");
struct nuc_ReportResult nuc_rg_read_report(struct nuc_StrView file) asm("nuc_rg-read-report");
int32_t nuc_rename_global_main(int32_t argc, void* argv) asm("nuc_rename-global-main");
int32_t nuc_rg_main(struct nuc_StrView path, int64_t line, int64_t col, struct nuc_StrView new_, bool apply, bool in_strings, struct nuc_Vector_nuc_StrView* roots, struct nuc_Vector_nuc_StrView* reports, struct nuc_RgOpts* opts) asm("nuc_rg-main");
