/* Fixture for tests/expected/cheader-opaque.out and the tests/fixtures/w3a-*
   rejection fixtures (Stage 15 W3a, design/stage15-stress-test/cheader.md §1.6)
   — opaque forward-declared C types.

   Deliberately self-contained rather than relying on <stdio.h>'s FILE: whether
   FILE is opaque depends on whether the host libc's struct _IO_FILE body uses
   constructs the C parser can model (glibc's uses bitfields, so it does not),
   and a rejection test must not depend on that. */

/* A pure opaque handle: declared, never defined. Legal only behind a pointer. */
struct CHOpaque;

/* An opaque tag reached through a typedef alias — the FILE / SDL_Window /
   Mix_Music idiom. `CHHandle` must be usable as `ptr:CHHandle`. */
typedef struct CHHandleImpl CHHandle;

/* A repeated forward declaration. glibc's <stdio.h> declares
   `struct _IO_FILE;` three times; the second and third must be no-ops. */
struct CHOpaque;

/* Forward declaration FIRST, definition LATER — the order real C headers use.
   The definition must upgrade the opaque entry in place, not collide with it. */
struct CHLater;
struct CHLater {
    int a;
    int b;
};

/* Same, but with a typedef alias registered while the tag was still opaque:
   upgrading the tag must propagate to the alias. Here the alias repeats the tag
   name (the common idiom), so both spellings are one registry entry. */
struct CHAliasedLater;
typedef struct CHAliasedLater CHAliasedLater;
struct CHAliasedLater {
    int v;
};

/* And with a DISTINCT alias name, so the alias really is a second registry
   entry linked to the tag by StructDef.alias-of — the case that actually
   exercises upgrade propagation (glibc's `typedef struct _IO_FILE FILE;`). */
struct CHRefImpl;
typedef struct CHRefImpl CHRef;
struct CHRefImpl {
    int q;
};

/* A tag forward-declared and then defined through a typedef whose body is
   parsed anonymously (`typedef struct Tag { … } Name;`). Both spellings must
   end up usable. */
struct CHTypedefLater;
typedef struct CHTypedefLater {
    int w;
} CHTypedefLater;
