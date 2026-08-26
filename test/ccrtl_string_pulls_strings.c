/* glibc's <string.h> pulls in <strings.h> under __USE_MISC, so a program that
   includes only <string.h> still sees strcasecmp/strncasecmp/bzero/ffs.
   busybox leans on exactly that: libbb.h includes <string.h> and never
   <strings.h>, and strcasecmp/strncasecmp were the single largest cause of
   "call to undeclared function" across a busybox sweep.

   The gate matters as much as the include. <strings.h> defines index(), and
   `index` is an extremely common local variable name — a strict-ISO
   translation unit must not acquire that name just because it asked for
   <string.h>. The strict half of this test is checked in a separate file so
   each half compiles under its own feature-test state; here the macro is on. */
#define _GNU_SOURCE 1
#include <string.h>

int printf(const char *, ...);

int main(void) {
  char buf[8];
  int i;

  printf("%d %d %d\n", strcasecmp("AbC", "aBc"),
         strcasecmp("a", "B") < 0, strcasecmp("B", "a") > 0);
  printf("%d %d\n", strncasecmp("AbCx", "aBcY", 3), strncasecmp("AbCx", "aBcY", 4) != 0);

  for (i = 0; i < 8; i++) buf[i] = 'q';
  bzero(buf, 8);
  for (i = 0; i < 8; i++) if (buf[i] != 0) { printf("bzero FAIL\n"); return 1; }
  printf("bzero ok\n");

  printf("%d %d %d\n", ffs(0), ffs(1), ffs(48));
  printf("%d\n", (int)(index("hello", 'l') - "hello"));
  return 0;
}
