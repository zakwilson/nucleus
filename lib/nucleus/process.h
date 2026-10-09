#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "string.h"
#include "allocator.h"
#include "core.h"

/* Generated from lib/nucleus/process.nuc by nucleusc --emit-cheader */

#define EXEC_FAILED_STATUS 127
#define PROC_CHUNK 65536
#define PROC_MODE_644 420
typedef struct nuc_ExitStatus {
    int32_t tag;
    union {
        int32_t exited;
        int32_t signaled;
    } payload;
} nuc_ExitStatus;

enum nuc_ExitStatus_tag {
    nuc_ExitStatus_exited = 0,
    nuc_ExitStatus_signaled = 1
};

struct nuc_ExitStatus nuc_wait_status_decode(int32_t wstatus) asm("nuc_wait-status-decode");
bool nuc_success_QMARK(struct nuc_ExitStatus* self);
int32_t nuc_exit_code(struct nuc_ExitStatus* self) asm("nuc_exit-code");
#ifndef NUC_INST_nuc_Vector_usize
#define NUC_INST_nuc_Vector_usize
typedef struct nuc_Vector_usize {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_Alloc alloc;
} nuc_Vector_usize;
#endif

typedef struct nuc_Command {
    struct nuc_String buf;
    struct nuc_Vector_usize offs;
    struct nuc_Vector_usize envs;
    int64_t cwd_off;
    bool search;
    bool capture;
    int64_t out_path_off;
    int64_t in_path_off;
    bool merge_err;
} nuc_Command;

size_t nuc_command_push_cstr(struct nuc_Command* self, struct nuc_StrView s) asm("nuc_command-push-cstr");
struct nuc_Command nuc_command(struct nuc_StrView prog);
void nuc_command_arg(struct nuc_Command* self, struct nuc_StrView a) asm("nuc_command-arg");
void nuc_command_cwd(struct nuc_Command* self, struct nuc_StrView dir) asm("nuc_command-cwd");
void nuc_command_search(struct nuc_Command* self, bool on) asm("nuc_command-search");
void nuc_command_env(struct nuc_Command* self, struct nuc_StrView k, struct nuc_StrView v) asm("nuc_command-env");
void nuc_command_capture(struct nuc_Command* self, bool on) asm("nuc_command-capture");
void nuc_command_stdout_path(struct nuc_Command* self, struct nuc_StrView path) asm("nuc_command-stdout-path");
void nuc_command_stdin_path(struct nuc_Command* self, struct nuc_StrView path) asm("nuc_command-stdin-path");
void nuc_command_stderr_to_stdout(struct nuc_Command* self, bool on) asm("nuc_command-stderr-to-stdout");
void nuc_drop_pnuc_Command(struct nuc_Command* self) asm("nuc_drop.pnuc_Command");
#ifndef NUC_INST_nuc_Vector_ptr
#define NUC_INST_nuc_Vector_ptr
typedef struct nuc_Vector_ptr {
    uint8_t* data;
    size_t len;
    size_t cap;
    struct nuc_Alloc alloc;
} nuc_Vector_ptr;
#endif

void nuc_command_argv(struct nuc_Command* self, struct nuc_Vector_ptr* out) asm("nuc_command-argv");
struct nuc_StrView nuc_env_key(uint8_t* e) asm("nuc_env-key");
void nuc_command_envp(struct nuc_Command* self, struct nuc_Vector_ptr* out) asm("nuc_command-envp");
typedef struct nuc_Process {
    int32_t pid;
    int32_t out_fd;
    int32_t err_fd;
    struct nuc_ExitStatus status;
} nuc_Process;

int32_t nuc_process_pid(struct nuc_Process* self) asm("nuc_process-pid");
/* spawn: uses an error-union or option type; not exported */
/* process-drain-one: uses an error-union or option type; not exported */
/* process-capture: uses an error-union or option type; not exported */
/* process-wait: uses an error-union or option type; not exported */
/* process-try-wait: uses an error-union or option type; not exported */
struct nuc_ExitStatus nuc_process_status(struct nuc_Process* self) asm("nuc_process-status");
/* process-kill: uses an error-union or option type; not exported */
typedef struct nuc_ChildExit {
    int32_t pid;
    struct nuc_ExitStatus status;
} nuc_ChildExit;

/* wait-any: uses an error-union or option type; not exported */
void nuc_process_detach(struct nuc_Process* self) asm("nuc_process-detach");
void nuc_drop_pnuc_Process(struct nuc_Process* self) asm("nuc_drop.pnuc_Process");
typedef struct nuc_Output {
    struct nuc_ExitStatus status;
    struct nuc_String out;
    struct nuc_String err;
} nuc_Output;

void nuc_drop_pnuc_Output(struct nuc_Output* self) asm("nuc_drop.pnuc_Output");
/* run: uses an error-union or option type; not exported */
