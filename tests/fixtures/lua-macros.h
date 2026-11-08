/* Header shapes the nuc-lua port met (ISSUE-012, 014, 024, 046). */
#define LM_FILEHANDLE "FILE*"
#define LM_MAJOR "5"
#define LM_MINOR "5"
#define LM_VERSION "Lua " LM_MAJOR "." LM_MINOR
#define LM_ESC "a\tb\x41"
#define _LM_FULL 0
#define _LM_LINE 1
typedef void (*lm_handler)(int);
#define LM_DFL ((lm_handler) 0)
#define LM_NOADDR ((void *) -1)
extern const char lm_ident[];
extern int lm_table[3];
int lm_call (lm_handler h);
