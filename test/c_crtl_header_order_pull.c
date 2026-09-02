/* The crtl impl auto-pull must not fire for a header re-entered through its
 * own include guard.
 *
 * pxx has no link step: completing a crtl `<header>` pulls its sibling
 * `lib/crtl/src/<name>.c`. Reaching a header a SECOND time while the first
 * instance is still being processed leaves an empty body (the guard is already
 * set) -- and pulling the impl at that moment compiles it against a header
 * that has not defined its macros yet.
 *
 * Measured 2026-09-02: <sys/types.h> gained an `#include <sys/select.h>`
 * (glibc has one, and busybox's libbb.h reaches fd_set only that way). With
 * <unistd.h> included FIRST, its line 6 pulls <sys/types.h> -> <sys/select.h>
 * -> src/sys/select.c -> <unistd.h> (guard-empty) -> src/unistd.c, whose every
 * _SC_*, X_OK and no_argument was still undefined. Nothing failed: an
 * undeclared identifier used as a value is a WARNING, so sysconf(_SC_PAGESIZE)
 * returned -1 and getopt_long compared required_argument = no_argument = 0.
 *
 * <unistd.h> FIRST is the whole point of this file -- the two other orders
 * (<sys/types.h> first, <sys/select.h> first) were both clean throughout.
 * Every row is an OBSERVABLE of src/unistd.c, not of the macro spelling: a
 * test that only printed X_OK would have passed while getopt_long was broken.
 */
#include <unistd.h>
#include <getopt.h>
#include <stdio.h>
#include <string.h>

static struct option longopts[4];

int main(void)
{
  char *argv[6];
  int c;
  int nfile;
  int nverb;

  printf("1 %ld\n", sysconf(_SC_PAGESIZE));
  printf("2 %ld\n", sysconf(_SC_CLK_TCK));
  printf("3 %d\n", sysconf(_SC_OPEN_MAX) > 0 ? 1 : 0);
  printf("4 %d %d %d %d\n", F_OK, X_OK, W_OK, R_OK);
  printf("5 %d %d %d\n", no_argument, required_argument, optional_argument);

  longopts[0].name = "file";
  longopts[0].has_arg = required_argument;
  longopts[0].flag = 0;
  longopts[0].val = 'f';
  longopts[1].name = "verbose";
  longopts[1].has_arg = no_argument;
  longopts[1].flag = 0;
  longopts[1].val = 'v';
  longopts[2].name = 0;
  longopts[2].has_arg = 0;
  longopts[2].flag = 0;
  longopts[2].val = 0;

  argv[0] = "prog";
  argv[1] = "--file=abc";
  argv[2] = "-v";
  argv[3] = "--verbose";
  argv[4] = "rest";
  argv[5] = 0;

  nfile = 0;
  nverb = 0;
  optind = 1;
  while ((c = getopt_long(5, argv, "f:v", longopts, 0)) != -1)
  {
    if (c == 'f') { nfile++; printf("6 f %s\n", optarg ? optarg : "(null)"); }
    else if (c == 'v') nverb++;
    else printf("6 ? %d\n", c);
  }
  printf("7 %d %d %s\n", nfile, nverb, argv[optind] ? argv[optind] : "(none)");
  return 0;
}
