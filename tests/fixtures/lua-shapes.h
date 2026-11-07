/* Shapes Lua's headers use throughout (nuc-lua ISSUE-002, ISSUE-003, ISSUE-026). */
typedef struct LS LS;
typedef int (*LCF)(LS *L);
extern long long (ls_twice) (long long n);
extern const char *(ls_name) (int i);
typedef struct LReg { const char *name; LCF func; } LReg;
extern void __attribute__((noreturn)) ls_die (const char *fmt, ...);
