/* Module A of the two-module static probe. Included, never compiled alone —
   it is an INPUT to test/cstatic_two_modules_distinct.c, which is what the
   Makefile runs.

   The whole point is that `who` here and `who` in cstatic_mod_b.c are two
   distinct functions with INTERNAL linkage, and that they must return
   DIFFERENT values. crtl's real instance of this shape (`static int sysret` in
   both fcntl.c and unistd.c) has two byte-identical bodies, so it cannot tell
   a correct bind from a wrong one — any test built on it passes either way.
   feature-c-two-same-named-file-scope-statics-share-one-procs-row */

static int who(void) { return 1; }

int from_a(void) { return who(); }

/* Taking the address must select the same body the call does. */
int (*a_addr(void))(void) { return who; }
