#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "string.h"
#include "prelude.h"

/* Generated from lib/process.nuc by nucleusc --emit-cheader */

#define EXEC_FAILED_STATUS 127
#define PROC_CHUNK 65536
#define PROC_MODE_644 420
typedef struct ExitStatus {
    int32_t tag;
    union {
        int32_t exited;
        int32_t signaled;
    } payload;
} ExitStatus;

enum ExitStatus_tag {
    ExitStatus_exited = 0,
    ExitStatus_signaled = 1
};

struct ExitStatus wait_status_decode(int32_t raw) asm("wait-status-decode");
bool success_QMARK(void* self);
int32_t exit_code(void* self) asm("exit-code");
typedef struct Command {
    struct String buf;
    void* offs;
    void* envs;
    int64_t cwd_off;
    bool search;
    bool capture;
    int64_t out_path_off;
    bool merge_err;
} Command;

size_t command_push_cstr(void* self, struct StrView s) asm("command-push-cstr");
struct Command command(struct StrView prog);
void command_arg(void* self, struct StrView a) asm("command-arg");
void command_cwd(void* self, struct StrView dir) asm("command-cwd");
void command_search(void* self, bool on) asm("command-search");
void command_env(void* self, struct StrView k, struct StrView v) asm("command-env");
void command_capture(void* self, bool on) asm("command-capture");
void command_stdout_path(void* self, struct StrView path) asm("command-stdout-path");
void command_stderr_to_stdout(void* self, bool on) asm("command-stderr-to-stdout");
void drop_pCommand(struct Command* self) asm("drop.pCommand");
void command_argv(void* self, void* out) asm("command-argv");
struct StrView env_key(uint8_t* e) asm("env-key");
void command_envp(void* self, void* out) asm("command-envp");
typedef struct Process {
    int32_t pid;
    int32_t out_fd;
    int32_t err_fd;
    struct ExitStatus status;
} Process;

int32_t process_pid(void* self) asm("process-pid");
/* spawn: uses an error-union or option type; not exported */
/* process-drain-one: uses an error-union or option type; not exported */
/* process-capture: uses an error-union or option type; not exported */
/* process-wait: uses an error-union or option type; not exported */
/* process-try-wait: uses an error-union or option type; not exported */
struct ExitStatus process_status(void* self) asm("process-status");
/* process-kill: uses an error-union or option type; not exported */
typedef struct ChildExit {
    int32_t pid;
    struct ExitStatus status;
} ChildExit;

/* wait-any: uses an error-union or option type; not exported */
void process_detach(void* self) asm("process-detach");
void drop_pProcess(struct Process* self) asm("drop.pProcess");
typedef struct Output {
    struct ExitStatus status;
    struct String out;
    struct String err;
} Output;

void drop_pOutput(struct Output* self) asm("drop.pOutput");
/* run: uses an error-union or option type; not exported */
