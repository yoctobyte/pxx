/* dprintf / vdprintf against the gcc oracle.
 *
 * crtl had neither, so busybox's ash did not compile (shell/ash.c:10475 uses
 * dprintf for trace output, where going through a FILE would interleave with
 * the shell's own buffered writes). Found attempting rung 2.
 *
 * The row that matters is the LONG one. vsnprintf reports the length it WOULD
 * have written, so an implementation that formats into a fixed buffer and
 * ignores that answer TRUNCATES -- and truncated output looks right and is
 * short, which is the failure mode that survives review. 2000 characters is
 * past any reasonable stack buffer, so a truncating implementation differs
 * from gcc here and nowhere else.
 */
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <stdarg.h>

static int viaVararg(int fd, const char *fmt, ...) {
  va_list ap; int r;
  va_start(ap, fmt);
  r = vdprintf(fd, fmt, ap);
  va_end(ap);
  return r;
}

int main(void) {
  char big[2001];
  int n;

  n = dprintf(1, "short %d %s\n", 42, "text");
  fflush(stdout);
  fprintf(stderr, "short returned %d\n", n);

  memset(big, 'x', sizeof big - 1);
  big[sizeof big - 1] = '\0';
  n = dprintf(1, "%s\n", big);
  fflush(stdout);
  fprintf(stderr, "long returned %d\n", n);

  n = viaVararg(1, "va %d\n", 7);
  fflush(stdout);
  fprintf(stderr, "va returned %d\n", n);

  n = dprintf(1, "%s", "");
  fprintf(stderr, "empty returned %d\n", n);
  return 42;
}
