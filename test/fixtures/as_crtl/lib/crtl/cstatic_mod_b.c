/* Module B of the two-module static probe — see cstatic_mod_a.c.

   Same name, different body, deliberately: 2 is not 1, so a call that binds to
   the wrong module's `who` is visible in the output instead of being masked by
   two identical implementations. */

static int who(void) { return 2; }

int from_b(void) { return who(); }

int (*b_addr(void))(void) { return who; }
