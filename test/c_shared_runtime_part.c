/* the second unit of c_shared_runtime_main.c */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

static int helper(void) { return 2; }
int part_helper(void) { return helper(); }

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
