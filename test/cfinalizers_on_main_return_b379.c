/* The C entry stub must run __pxx_run_finalizers before exiting.

   The stub is `call main; exit_group(retval)`, so a plain `return` from main
   used to bypass the finalizer shell entirely — the commonest exit path in C.
   That is why crtl could not implement atexit: handlers would fire for exit()
   and be SILENTLY dropped for `return`, which looks implemented and produces a
   plausible wrong result. A body-less declaration at least fails loudly.

   This test pins the half that is the compiler's: main's return value must
   survive the finalizer call unharmed on every target. The finalizers-actually-
   ran half needs a registered handler, which is crtl's atexit table
   (feature-b-crtl-last-seven-unimplemented-declarations) — verified during
   development by temporarily giving pxxcio a finalization section, which
   printed AFTER "main-returns" and left the exit code intact.

   feature-c-entry-stub-must-run-finalizers

   exits 42 on success. */
#include <stdio.h>

int main(void)
{
    printf("main-returns\n");
    return 42;
}
