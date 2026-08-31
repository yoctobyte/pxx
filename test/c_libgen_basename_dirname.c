/* crtl's <libgen.h>: basename() and dirname(), row for row against glibc.
   Every row here was produced by a glibc-built binary of this same file. */
#include <stdio.h>
#include <string.h>
#include <libgen.h>

static const char *cases[] = { "/usr/lib", "/usr/", "usr", "/", ".", "..", "",
  "//", "///", "////", "a//b//", "/a", "a/", "///a///b///", "foo.txt", "./x", 0 };

int main(void)
{
  int i;
  char b1[64], b2[64];

  for (i = 0; cases[i]; i++) {
    strcpy(b1, cases[i]);
    strcpy(b2, cases[i]);
    printf("[%s] base=[%s] dir=[%s]\n", cases[i], basename(b1), dirname(b2));
  }
  { char *n = 0; printf("null base=[%s] dir=[%s]\n", basename(n), dirname(n)); }
  return 0;
}
