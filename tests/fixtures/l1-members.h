/* Fixture for run_l1_member_opaque (Stage 16 L1,
   design/stage16-ergonomics/c-header-layout.md §1.3/§3.1).

   `c-parse-type` raises `g-cheader-unrep` on five distinct shapes; before L1 the
   struct-body loop ignored the flag and stored the returned `ptr` as the field
   type, so a member the parser could not represent became a silently WRONG
   layout (§1.2: `struct __jmp_buf_tag` at 24 bytes against C's 200) rather than
   a refusal. Each `l1_m_*` below drives one of those five raise sites through a
   struct MEMBER, which is the position L1 added.

   What the gate asserts is that the failure is SAFE, not merely that it
   happened: a located error naming this file and the struct's own line, and NO
   `%X = type` line for the struct anywhere in the emitted module. A wrong
   layout compiles fine, which is why "it compiled" is never the assertion.

   The two `l1_ok_*` rows at the bottom are the positive controls: they must
   still get exact layouts, so a future "fix" cannot pass this gate by making
   every C struct opaque. */

/* ---- the five unrepresentable member shapes ------------------------------ */

/* c-parse-type:596 — a by-value `long double`. */
struct l1_m_long_double { long double d; int b; };

/* c-parse-type:599 — a by-value name the typedef table records as known but
   unrepresentable. `long double` again, one level of indirection away, so the
   member spelling itself looks perfectly ordinary. */
typedef long double l1_ld_t;
struct l1_m_unrep_typedef { l1_ld_t d; int b; };

/* c-parse-type:554 — a by-value `struct Tag` whose tag is opaque. */
struct l1_opaque_tag;
struct l1_m_opaque_tag { struct l1_opaque_tag o; int b; };

/* c-parse-type:602 — a by-value name that resolves to nothing at all. */
struct l1_m_unknown_tag { struct l1_nowhere_at_all z; int b; };

/* c-parse-type:529 — a by-value aggregate whose `{…}` body the parser could not
   read. A bitfield is the shape design/stage3c.md defers, reached here through a
   typedef so the enclosing member is an ordinary name. */
typedef struct { int x; int y:3; } l1_bitfield_t;
struct l1_m_bad_body { l1_bitfield_t t; int b; };

/* ---- positive controls --------------------------------------------------- */

/* Nothing exotic: must still emit `%l1_ok_plain = type { i32, i32 }`. */
struct l1_ok_plain { int a; int b; };

/* A typedef-hidden ARRAY member. §1.2 measured this as the silent-wrong case
   that motivated L1 — but L2 gave `c-typedef-record` a real `(array T N)` to
   store, so it is now REPRESENTABLE and must carry the extent. Kept here (and
   asserted as a layout, not as an error) because it is the row the design's
   §5 gate table still describes as opaque. */
typedef int l1_arr_t[4];
struct l1_ok_hidden_array { l1_arr_t a; int b; };
