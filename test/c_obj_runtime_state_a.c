/* Half A of the two-object runtime-state test -- see the Makefile block
   4b-septies in test-emit-obj, and
   bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link.

   Every routine here TOUCHES a different piece of pxx's bundled C runtime, and
   half B observes the result. The point is not that the calls work -- they
   worked when each object had a private runtime -- it is that A and B must be
   looking at the SAME heap, the same errno and the same optind. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void *ra_alloc(void)
{
  char *p = (char *)malloc(64);
  strcpy(p, "TU-A");
  return p;                      /* half B frees this: one heap, or corruption */
}

void ra_fail_open(void)
{
  FILE *f = fopen("/definitely/not/here/xyz", "r");
  if (f) fclose(f);              /* sets errno to ENOENT, for B to read */
}

void ra_scan(int argc, char **argv)
{
  while (getopt(argc, argv, "u") != -1)
    ;                            /* advances optind, for B to read */
}
