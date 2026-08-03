/* C-on-xtensa (and riscv32) as a RELOCATABLE OBJECT — the only shape that means
   anything on an ESP: there is no OS, no syscall ABI and no standalone
   executable, so the artifact is a .o the IDF links, exporting app_main.

   The C driver used to run the program-entry-stub emitter unconditionally, so
   `--target=xtensa` rejected every C program outright ("C program entry stub not
   implemented for this target yet") and lib/crtl could not be exercised on the
   primary ESP target at all. bug-cfront-no-entry-stub-for-xtensa

   The LONG_MAX guard rides along because it is what the coverage was wanted for:
   <limits.h>'s target-width LONG_MAX was 64-bit on every target until 2026-08-02,
   and this is the compile-time proof the 32-bit value reaches xtensa. Compiled
   for 32-bit targets only — see the Makefile. */

#include <limits.h>

#if LONG_MAX != 2147483647L
#error LONG_MAX is not the 32-bit value on this target
#endif

#if INT_MAX != 2147483647
#error INT_MAX is not the 32-bit value on this target
#endif

int captured;

void ext_notify(int v);

int app_main(void) {
  captured = (int)(sizeof(long) == 4);
  ext_notify(captured);
  return captured;
}
