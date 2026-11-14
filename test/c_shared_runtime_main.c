/* --shared-runtime: two translation units, linked by pascal26 --link with no
   runtime named; --link must build/cache it and add it. Exercises the runtime
   STATE a unit reaches by name (stdout, environ, errno, optind), a static name
   in both units, and memory allocated in one object and freed in the other.
   decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

char *part_make(const char *s);
int part_helper(void);
int part_errno(void);

static int helper(void) { return 1; }

int main(int argc, char **argv) {
  int c, n = 0;
  char *p;
  while ((c = getopt(argc, argv, "ab")) != -1) n++;
  printf("opts %d optind %d\n", n, optind);
  printf("helpers %d %d\n", helper(), part_helper());
  p = part_make("abc");
  printf("made %s\n", p);
  free(p);
  printf("env %s\n", getenv("PXX_SR_TEST") ? getenv("PXX_SR_TEST") : "(none)");
  printf("errno %d\n", part_errno() == errno && errno == ENOENT);
  fflush(stdout);
  return 0;
}
