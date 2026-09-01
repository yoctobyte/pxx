/* %m -- glibc's "insert strerror(errno) here", used by essentially every
 * errno-carrying diagnostic in busybox (bb_perror_msg and friends).
 *
 * crtl treated it as an UNKNOWN conversion and emitted it verbatim, so
 * busybox's ash reported `can't fork: %m' and the actual reason was lost.
 * That made it a bug about DIAGNOSING OTHER BUGS: the fork failure underneath
 * it could not be read until this worked. Found attempting rung 2
 * (feature-c-corpus-busybox-multi-applet).
 *
 * ROW 2 IS THE POINT OF THE TEST. %m takes NO ARGUMENT. An implementation that
 * reads a vararg for it prints something plausible for the %m itself and then
 * shifts every later specifier by one, which this file already carries two
 * other comments about in other conversions. A test that only checked %m in
 * isolation passes over that.
 *
 * Compared against gcc, so the strerror TEXT is asserted too, not just the
 * fact that something was substituted.
 */
#include <stdio.h>
#include <errno.h>
#include <string.h>

int main(void) {
  char b[128];

  /* 1: the plain substitution. */
  errno = ENOENT;
  snprintf(b, sizeof b, "err: %m");
  printf("1 [%s]\n", b);

  /* 2: NO ARGUMENT CONSUMED. If %m eats the 42, the %d prints garbage and the
        trailing marker moves. Two specifiers after it, deliberately. */
  errno = EINVAL;
  snprintf(b, sizeof b, "%m|%d|%s", 42, "tail");
  printf("2 [%s]\n", b);

  /* 3: it reads errno at CONVERSION time, not at call time -- two %m in one
        format still both see the same errno, and a later change is visible. */
  errno = EACCES;
  snprintf(b, sizeof b, "%m/%m");
  printf("3 [%s]\n", b);

  /* 4: width and precision apply as they do to %s. */
  errno = ENOENT;
  snprintf(b, sizeof b, "[%.4m][%12m]");
  printf("4 [%s]\n", b);

  /* 5: errno == 0 is not special-cased by glibc; it is just entry 0. */
  errno = 0;
  snprintf(b, sizeof b, "%m");
  printf("5 [%s]\n", b);

  /* 6: and %m still agrees with strerror() reached the ordinary way. */
  errno = EINVAL;
  snprintf(b, sizeof b, "%m");
  printf("6 %d\n", strcmp(b, strerror(EINVAL)) == 0);

  return 0;
}
