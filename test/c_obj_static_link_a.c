/* `static' on a C FUNCTION is internal linkage (C 6.2.2p3), so the object must
   carry it as a LOCAL symbol. pxx emitted every C-convention proc GLOBAL, and
   busybox's libbb.h -- which defines bb_ascii_isalnum, bb_strtoi32,
   is_tty_secure, new_tls_state and a dozen more as `static ALWAYS_INLINE' --
   is included by every translation unit, so an 82-object link died on
   `multiple definition' before reaching anything the program wrote.

   THE DISCRIMINATOR IS NOT THAT IT LINKS. Weakening these instead of localising
   them also links, and is wrong: the linker would then keep ONE body and both
   translation units would call it. So this file and its sibling define the same
   two names with DIFFERENT bodies, and the answer says which happened. Under
   correct internal linkage each file calls its own; under a weak fix both call
   whichever survived, and the printed numbers change.

   bug-a-static-c-functions-are-emitted-as-global-symbols
   feature-c-corpus-busybox-userland-by-separate-compilation */

static int shared_counter = 10;

static int shared_helper(int x) { return x + 1; }

/* NOT static, and it is the positive control for the symbol-binding assertion
   in the Makefile: a writer that localised EVERYTHING would satisfy a check
   that only looked for LOCAL, and would export nothing at all. */
int a_probe(void) { return shared_helper(shared_counter); }
