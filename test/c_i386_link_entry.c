/* The entry contract of tools/pxxcrt_i386.S, the _start for linking pxx's
   i386 objects with the host ld (tools/pxx_link_i386.sh): argv, environ, an
   .init_array constructor, and exit(main's value) through crtl so atexit runs
   and buffered stdout is flushed. The output equals the same file built as a
   pxx i386 program. feature-c-i386-link-for-c-objects */
#include <stdio.h>
#include <stdlib.h>
static void bye(void) { printf("atexit ran\n"); }
static int ctor_ran;
__attribute__((constructor)) static void ctor(void) { ctor_ran = 1; }
int main(int argc, char **argv) {
  atexit(bye);
  printf("argc=%d argv1=%s ctor=%d env=%s", argc, argc > 1 ? argv[1] : "-", ctor_ran, getenv("PXXT") ? getenv("PXXT") : "unset");
  return 5;
}
