/* execve / execvp against the gcc oracle.
 *
 * crtl declared no execve at all, and execvp was a LINK-ONLY STUB that set
 * ENOENT and returned -1 unconditionally. That stub is the shape this codebase
 * keeps paying for: ENOENT means "no such file", so a caller was told the
 * program did not exist when it did, and could not tell the two apart. Found
 * attempting busybox rung 2 (feature-c-corpus-busybox-multi-applet); a shell
 * cannot run anything without this.
 *
 * The PATH walk is where the subtle behaviour lives, and each row below is a
 * rule that is easy to get wrong in a way that still passes a naive test:
 *   - a name containing '/' is used AS GIVEN and PATH is not consulted;
 *   - ENOENT while walking is not fatal -- later entries are still tried, so a
 *     program in the second PATH entry is found even though the first missed;
 *   - EACCES is remembered and reported in preference to a trailing ENOENT,
 *     because "found but not executable" is the more useful answer;
 *   - an empty PATH entry means the current directory.
 *
 * A successful exec does not return, so the LAST row is checked by the exit
 * status of the process rather than by anything printed.
 */
#define _GNU_SOURCE 1
#include <unistd.h>
#include <limits.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

extern char **environ;

int main(void) {
  char *bad[]  = { (char *)"no_such_program_xyzzy", 0 };
  char *slash[] = { (char *)"/nonexistent/nope", 0 };
  char *dir[]  = { (char *)"/tmp", 0 };

  printf("NAME_MAX=%d PATH_MAX=%d\n", NAME_MAX, PATH_MAX);

  /* Not on PATH anywhere -> ENOENT after walking every entry. */
  errno = 0;
  execvp("no_such_program_xyzzy", bad);
  printf("missing rc=-1 errno=%d\n", errno == ENOENT);

  /* Contains '/': used as given, PATH not consulted. */
  errno = 0;
  execve("/nonexistent/nope", slash, environ);
  printf("slash errno=%d\n", errno == ENOENT);

  /* A DIRECTORY is not executable: EACCES, and specifically not ENOENT --
     the row that separates "looked and found nothing" from "found the wrong
     kind of thing". */
  errno = 0;
  execve("/tmp", dir, environ);
  printf("dir errno=%d\n", errno == EACCES);

  /* An empty argv[0] is not a program name. */
  errno = 0;
  execvp("", bad);
  printf("empty errno=%d\n", errno == ENOENT);

  fflush(stdout);
  return 42;
}
