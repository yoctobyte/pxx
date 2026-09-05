/* Two same-named file-scope statics in two C MODULES, with DIFFERENT bodies.

   THE SEMANTICS BEING ASSERTED ARE THE MULTI-TU ONES, and the oracle is gcc
   compiling it that way. C gives a file-scope `static` internal linkage, so
   `who` in fixtures/cstatic_mod_a.c and `who` in fixtures/cstatic_mod_b.c are
   two distinct functions when those files are two translation units:

     gcc -DSEPARATE_TU test/cstatic_two_modules_distinct.c \
         test/fixtures/cstatic_mod_a.c test/fixtures/cstatic_mod_b.c
     -> 1 1 / 2 2 / 3 1 / 4 2 / 5 1

   pxx reaches those same answers from ONE buffer. It has to: the preprocessor
   inlines every include, and crtl's modules are pulled into that same buffer,
   so `static int sysret` in fcntl.c and in unistd.c arrive as one translation
   unit. Module attribution (CModRange*, CModuleOfTok) is what keeps them two
   functions, and this file is that model's discriminating case.

   SO DO NOT RUN THE ORACLE THE WAY PXX RUNS THIS FILE. Without -DSEPARATE_TU,
   gcc sees one TU and correctly rejects it — `error: redefinition of 'who'`.
   That is not a divergence being papered over: a unity build genuinely is one
   TU, and pxx's single-buffer model is an accommodation crtl's pull requires.
   The claim under test is that the accommodation produces MULTI-TU semantics,
   which is why the oracle is the multi-TU build and not this spelling.

   WHY NOT REUSE test/cstatic_two_modules.c. That one uses crtl's real instance,
   `static int sysret` in both fcntl.c and unistd.c — and those two bodies are
   BYTE-IDENTICAL, so it cannot tell a correct bind from a wrong one. It would
   keep passing if every call bound to the other module's copy. These bodies
   return 1 and 2.

   WHAT EACH ROW IS WORTH, ABLATED RATHER THAN ASSUMED. Built against the
   compiler with the fix stashed out (47618f77c240), this file prints:

       1 1 / 2 2 / 3 2 / 4 2 / 5 0        <- pre-fix
       1 1 / 2 2 / 3 1 / 4 2 / 5 1        <- with the fix, and gcc's multi-TU answer

   Rows 1 and 2 were ALREADY CORRECT before the row split, because each call
   site keeps a CallFixTarget snapshot of the body current when it was compiled
   and stays BAKED. They are a regression control on the split, nothing more.

   ROW 3 IS A WRONG VALUE, and it corrects the ticket. Taking the address of a
   `static` did NOT go through the call path's snapshot — `a_addr()` returned
   module B's body, so module A's own function pointer called the wrong
   function and returned 2. The ticket said this was "not a wrong-answer bug
   today"; that is true of CALLS and false of function POINTERS.

   ROW 4 CANNOT FAIL ON ITS OWN and is kept only as row 3's pair. Pre-fix both
   pointers resolved to B, and B's answer is 2 — which is also row 4's expected
   value, so it is right for the wrong reason. Read it beside row 3 or not at
   all.

   ROW 5 states the claim directly: two distinct functions, two addresses.

   The object-level cost is separate again — a baked displacement has no symbol
   to relocate against — and the Makefile asserts it with `--emit-obj
   --function-sections`: pinned-target 7 pre-fix (`who` plus crtl's six
   `sysret`), 0 with the fix, and two LOCAL `who` symbols at different
   addresses in .symtab, which is what gcc emits for the multi-TU build.

   feature-c-two-same-named-file-scope-statics-share-one-procs-row */

extern int printf(const char *, ...);

#ifdef SEPARATE_TU
/* The oracle build: three translation units, linked. */
extern int from_a(void);
extern int from_b(void);
extern int (*a_addr(void))(void);
extern int (*b_addr(void))(void);
#else
/* The pxx build: one buffer, two modules. */
#include "fixtures/cstatic_mod_a.c"
#include "fixtures/cstatic_mod_b.c"
#endif

int main(void) {
  int (*pa)(void) = a_addr();
  int (*pb)(void) = b_addr();

  /* 1,2: a direct call from each module reaches that module's own body. */
  printf("1 %d\n", from_a());
  printf("2 %d\n", from_b());

  /* 3,4: and so does a function POINTER taken inside each module — the decay
     path resolves the name separately from the call path, so it is its own
     row rather than a restatement of the two above. */
  printf("3 %d\n", pa());
  printf("4 %d\n", pb());

  /* 5: the two are genuinely distinct functions, not one shared body. If the
     split did not happen, both addresses are the same address. */
  printf("5 %d\n", pa != pb);
  return 0;
}
