/* Two shapes lua.h and lauxlib.h use throughout (nuc-lua ISSUE-002, ISSUE-003). */
typedef struct LS LS;
typedef int (*LCF)(LS *L);
extern long long (ls_twice) (long long n);
extern const char *(ls_name) (int i);
typedef struct LReg { const char *name; LCF func; } LReg;
