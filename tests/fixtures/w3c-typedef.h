/* Stage 15 W3c (design/stage15-stress-test/cheader.md §1.4): the typedef matrix.
 *
 * Before W3c, `c-parse-type` resolved every name it did not recognize as a
 * builtin to `ptr` — so EVERY declaration below imported as `declare ptr @f(...)`
 * regardless of what it actually returns, and `size_t` worked only because
 * c-type-to-nucleus hardcodes that one name. The emitted `declare` line for each
 * function here is asserted exactly by run_w3c_typedef in tests/run-tests.sh:
 * the point is the SIGNATURE, not that the header compiles — every wrong row
 * compiled fine before.
 */

/* --- typedef to a builtin, one level and multi-level ------------------- */
typedef long int w3c_off_base;
typedef w3c_off_base w3c_off;          /* two levels */
typedef w3c_off w3c_off3;              /* three */
typedef unsigned char w3c_u8;
typedef unsigned int w3c_u32;
typedef short w3c_i16;
typedef int w3c_int;                   /* the one-level typedef of a builtin */
typedef float w3c_f32;
typedef double w3c_f64;
typedef unsigned long long w3c_u64;

/* --- typedef to a pointer type ---------------------------------------- */
typedef char *w3c_str;
typedef const char *w3c_cstr;
typedef w3c_off *w3c_offp;             /* pointer to a typedef'd scalar */

/* --- function-pointer typedef ----------------------------------------- */
/* The trap W3b recorded: a naive fallback reads `int` as the declarator and
 * parses this as a function literally named `int`. */
typedef int (*w3c_handler)(int);
typedef void (*w3c_voidfn)(void);

/* --- enum, named and anonymous ---------------------------------------- */
typedef enum { W3C_A, W3C_B } w3c_enum;
enum w3c_tagged { W3C_C, W3C_D };

/* --- typedef of an aggregate (W3a's path, must not regress) ----------- */
struct w3c_opaque_tag;
typedef struct w3c_opaque_tag w3c_opaque;
typedef struct { int a; int b; } w3c_pair;

/* --- typedef to an array: known name, no Nucleus representation ------- */
typedef int w3c_vec4[4];

/* --- the declarations under test -------------------------------------- */
extern w3c_off  w3c_f_off(int fd);
extern w3c_off3 w3c_f_off3(void);
extern w3c_u8   w3c_f_u8(void);
extern w3c_u32  w3c_f_u32(void);
extern w3c_i16  w3c_f_i16(void);
extern w3c_int  w3c_f_int(void);
extern w3c_f32  w3c_f_f32(void);
extern w3c_f64  w3c_f_f64(void);
extern w3c_u64  w3c_f_u64(void);
extern size_t   w3c_f_size(void);
extern int      w3c_f_takes(w3c_off a, w3c_u8 b, w3c_u32 c, w3c_i16 d);

extern w3c_str  w3c_f_str(w3c_cstr s, w3c_offp p);
extern void     w3c_f_handler(w3c_handler h, w3c_voidfn v);
extern w3c_enum w3c_f_enum(enum w3c_tagged t);
extern w3c_opaque *w3c_f_opaque(w3c_opaque *h);
extern int      w3c_f_pairp(w3c_pair *p);

/* A by-value use of the array typedef: recorded as known-but-unrepresentable,
 * so this declaration is SKIPPED rather than silently given the element ABI. */
extern int      w3c_f_vec(w3c_vec4 v);

/* A function declaration whose first token is `struct`/`union` and which has no
 * `extern`. W3b recorded this as silently dropped: the top-level dispatch routed
 * it to the type parser, which registered the tag and gave up, and since nothing
 * was synthesized the validity gate could not see it either. glibc always writes
 * `extern` so it never showed there; musl deliberately omits it. */
struct w3c_noext_tag;
struct w3c_noext_tag *w3c_f_noextern(int a);
union w3c_noext_u;
union w3c_noext_u *w3c_f_noextern_u(int a);

/* Struct field typing — the W3a-recorded `Mix_Chunk.volume` shape, where the
 * §1.4 defect showed up in a FIELD rather than a return type. */
struct w3c_fields {
  w3c_u8  vol;
  w3c_u32 len;
  w3c_off pos;
  w3c_str name;
};
