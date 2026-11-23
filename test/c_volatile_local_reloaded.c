/* A C function that mentions `volatile` keeps every reload: pxx drops the
 * qualifier, so the -O2 store->reload pass cannot tell a volatile local
 * from a plain one and skips the whole body. Row c_volrl26 checks that
 * `vx` is never marked and `px`, in a plain function, is.
 * feature-c-toybox-size-gap-literal-headers-call-realign-no-regalloc */
#include <stdio.h>
static int vol(int a) { volatile int vx = a; vx = vx + 1; return vx * 2; }
static int plain(int a) { int px = a; px = px + 1; return px * 2; }
int main(void) {
  printf("%d %d\n", vol(4), plain(4));
  return 0;
}
