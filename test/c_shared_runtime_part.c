/* the second unit of c_shared_runtime_main.c */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <assert.h>

static int helper(void) { return 2; }
/* assert and __builtin_popcount lower onto crtl's __pxx_* helpers, which a
   --shared-runtime object leaves undefined for the runtime object to supply */
int part_helper(void) {
  assert(helper() == 2);
  return __builtin_popcount(3u) == 2 ? helper() : -1;
}

char *part_make(const char *s) {
  char *p = malloc(strlen(s) + 2);
  strcpy(p, s);
  strcat(p, "!");
  fputs("part writes to stdout\n", stdout);
  return p;
}

int part_errno(void) {
  FILE *f = fopen("/nonexistent/pxx-shared-runtime", "r");
  if (f) fclose(f);
  return errno;
}
