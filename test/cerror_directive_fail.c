/* `#error` in a LIVE branch must STOP the compile — this file must never build.
   Gated with the must-fail idiom: the Makefile greps the diagnostic for the
   message text, so "it failed" is not enough, it has to fail for this reason.

   Before the fix the preprocessor had no `error` arm and no unknown-directive
   fallback, so this compiled clean, main ran, and the guard's whole point was
   lost. bug-cfront-error-directive-silently-ignored */

#if 1
#error configuration is unsupported
#endif

int main(void) { return 0; }
