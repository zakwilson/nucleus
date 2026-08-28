/* Stage 16 C1 (design/stage16-ergonomics/cheader-parser-vs-libclang.md §3): a
   bare `unsigned`/`signed` IS a type — implicitly `unsigned int`/`signed int`.
   Neither ended the declaration-specifier run, so the DECLARATOR name became
   the base type and the enclosing struct was abandoned. Sizes are asserted
   against the platform C compiler in the same harness run, never hardcoded. */
struct S16U01 { unsigned a; int b; };
struct S16U02 { signed a; int b; };
struct S16U03 { unsigned char a; int b; };
struct S16U04 { unsigned long a; int b; };
/* Declaration specifiers are order-independent, so these are the same types. */
struct S16U05 { long unsigned a; int b; };
struct S16U06 { short unsigned a; int b; };
struct S16U07 { signed char a; int b; };
struct S16U08 { unsigned int a; int b; };

unsigned s16u_f(void);
signed s16u_g(unsigned x, signed y);

/* C2: a parenthesised declarator the parser does not read. It must be recorded
   with a reason, not dropped silently. */
int (s16u_odd)(int);
