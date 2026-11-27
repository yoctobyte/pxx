/* An --emit-obj --system-libs object is linked against the HOST libc (here by
   gcc, test/c_system_libs_host_names_main.c), so every name it imports must be
   one that libc exports, and every struct it hands to libc must be libc's
   layout. Found linking a pxx-built libwlroots into a gcc-built Panorama:
     - gcc's bit builtins became calls to crtl's __pxx_builtin_* (refused at
       compile time: no libc has them);
     - time() was crtl's __crtl_time; isfinite and signbit were functions,
       which glibc has only as macros;
     - struct stat was crtl's 120-byte order, and glibc's fstat writes 144
       bytes in the kernel's order.
   bug-c-system-libs-objects-import-crtl-only-names,
   bug-crtl-struct-stat-is-not-glibc-s-layout-on-x86-64 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>
#include <sys/stat.h>

struct guarded { struct stat st; long canary[4]; };

int hn_run(void) {
  volatile unsigned int u = 0xF0F00001u;
  volatile unsigned long long q = 0x8000000000000100ull;
  printf("popcount %d %d\n", __builtin_popcount(u), __builtin_popcountll(q));
  printf("clz %d %d ctz %d %d\n", __builtin_clz(u), __builtin_clzll(q),
         __builtin_ctz(u), __builtin_ctzll(q));
  printf("ffs %d %d parity %d\n", __builtin_ffs(u), __builtin_ffs(0), __builtin_parity(u));
  printf("bswap %x %x\n", (unsigned)__builtin_bswap16(0x1234), __builtin_bswap32(0x12345678u));

  time_t a, b = 0;
  a = time(&b);
  printf("time %s\n", (a > 1700000000 && a == b) ? "ok" : "BAD");

  volatile double one = 1.0, zero = 0.0, mz = -0.0;
  printf("isfinite %d %d signbit %d %d isnan %d\n", isfinite(one) != 0,
         isfinite(one / zero) != 0, signbit(mz) != 0, signbit(one) != 0,
         isnan(zero / zero) != 0);

  FILE *f = tmpfile();
  if (!f) { printf("tmpfile failed\n"); return 1; }
  fwrite("0123456789abc", 1, 13, f);
  fflush(f);
  struct guarded g;
  memset(&g, 0x5A, sizeof g);
  int r = fstat(fileno(f), &g.st);
  printf("fstat %d reg %d size %ld nlink %lu blksize-positive %d\n", r,
         S_ISREG(g.st.st_mode) ? 1 : 0, (long)g.st.st_size,
         (unsigned long)g.st.st_nlink, g.st.st_blksize > 0);
  printf("canary %s\n", g.canary[0] == 0x5A5A5A5A5A5A5A5AL ? "intact" : "OVERWRITTEN");
  fclose(f);
  return 0;
}
