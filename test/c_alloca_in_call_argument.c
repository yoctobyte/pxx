/* SPDX-License-Identifier: Zlib */
/*
 * alloca() evaluated INSIDE another call's argument list.
 *
 * x86-64's call sequence saves the caller's rsp below the outgoing argument
 * area and restores it with a FIXED offset from rsp. alloca moves rsp, so an
 * alloca evaluated while arguments are being pushed shifted that offset out
 * from under the restore and rsp came back holding whatever the alloca'd bytes
 * contained. Measured on busybox getopt32.c:373, `strcpy(alloca(len + 1),
 * applet_opts)`: control left for an address inside asctime_r, three bytes
 * into a seven-byte instruction. No diagnostic, and a backtrace naming a
 * function the program never calls.
 *
 * The parser now lifts each alloca in an argument list into a temporary
 * evaluated before the call. Every row here is a differential against a
 * glibc-built binary of this same file.
 *
 * `dup` must stay valid AFTER later allocas and later calls: that is the row
 * that catches a "fix" which merely stops the crash by handing back memory the
 * next call overwrites.
 */
#include <stdio.h>
#include <string.h>
#include <alloca.h>

static int shout(const char *s) { return printf("[%s]\n", s); }

int main(void)
{
  const char *s = "hello";
  char *d = strcpy(alloca(strlen(s) + 1), s);
  printf("dup: [%s]\n", d);

  /* one level deeper: the alloca is inside an argument of a call that is
     itself an argument. */
  shout(strcpy(alloca(strlen(s) + 1), s));

  /* two allocas in ONE argument list, both live at the same time */
  printf("two: %d\n", strcmp(strcpy(alloca(8), "ab"),
                             strcpy(alloca(8), "ab")) == 0);

  /* an alloca whose SIZE is itself an alloca-dependent expression */
  { char *n = alloca(4); n[0] = 8; n[1] = 0;
    printf("sized: %d\n", (int)strlen(strcpy(alloca((size_t)n[0]), "1234567"))); }

  /* a plain alloca, the shape that always worked -- the control */
  { char *q = alloca(32); memset(q, 'x', 31); q[31] = 0; printf("plain: %s\n", q); }

  printf("still here: %s\n", d);
  return 0;
}
