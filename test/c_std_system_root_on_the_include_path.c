/* `-I/usr/include/x86_64-linux-gnu`, a STANDARD system directory, is ignored,
 * as gcc ignores it. `pkg-config --cflags gtk+-3.0` emits it on some distros
 * (Ubuntu 24.04), and honouring it put the host libc's sys/types.h ahead of
 * pxx's crtl headers: "conflicting types for typedef '__pid_t'" and
 * "... 'int64_t'", so seven lib/pcl units failed on one box only. The row
 * compiles this WITH that -I. On a host without the directory the -I is
 * inert either way. */
#include <sys/types.h>
#include <stdint.h>
#include <stdio.h>
int main(void) {
  pid_t p = 42; int64_t q = -5;
  printf("pid %d int64 %lld\n", (int)p, (long long)q);
  return 0;
}
