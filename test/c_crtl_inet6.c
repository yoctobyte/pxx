/* SPDX-License-Identifier: Zlib */
/* inet_ntop/inet_pton for AF_INET6, diffed against glibc.

   THIS EXISTS BECAUSE THE AAAA PATH WAS DEAD AND FAILED AS A WRONG ANSWER.
   crtl's inet_ntop refused AF_INET6 and returned NULL; test/c_crtl_resolv.c's
   AAAA row then printed its caller's UNINITIALISED buffer, which still held
   the PREVIOUS record's IPv4 address. `2001:db8::1' came out as
   `93.184.216.34'. Nothing errored, and a reader would have called it a
   parser bug.

   THE ROUND TRIP IS PRINTED IN BOTH DIRECTIONS -- the 16 binary bytes AND the
   text they render back to -- because pton and ntop can be wrong in
   mirror-image ways and a text-to-text round trip passes when they are. The
   binary row is what pins each one separately.

   CANONICAL FORM IS THE POINT OF HALF THESE ROWS. RFC 5952 fixes ONE spelling
   per address: lowercase, no leading zeros, the LONGEST zero run compressed,
   the LEFTMOST winning a tie, and never "::" for a single zero group. Rows
   like "1:0:0:2:0:0:0:3" (two runs, the second longer) and "::1:0:0:0:0"
   (a tie decided by position) are there because an implementation that picks
   the wrong run produces a DIFFERENT STRING FOR THE SAME ADDRESS, and every
   textual comparison a program makes then fails for a reason nobody can see.

   THE REJECTION ROWS CARRY THEIR OWN WEIGHT. "1::2::3" (two "::"),
   "1:2:3:4:5:6:7:8:9" (too many groups), "12345::" (a five-digit group) and
   ":1:2:3:4:5:6:7" (a leading lone colon) are each accepted by at least one
   naive parser, and each would silently produce an address that is not the
   one written. */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <arpa/inet.h>
static const char *cases[] = {
  "::", "::1", "1::", "2001:db8::1", "2001:0db8:0000:0000:0000:0000:0000:0001",
  "fe80::1%0", "ff02::2", "2001:db8:0:1:0:0:0:1", "2001:db8:1:0:0:1:0:1",
  "0:0:0:0:0:0:0:0", "1:0:0:2:0:0:0:3", "1:2:3:4:5:6:7:8",
  "::ffff:192.0.2.128", "::192.0.2.128", "::ffff:0:0",
  "0:0:0:0:0:ffff:1.2.3.4", "abcd:ef01:2345:6789:abcd:ef01:2345:6789",
  "::1:0:0:0:0", "1:0:0:0:0:2:0:0",
  /* must all be refused */
  "1::2::3", ":::", "1:2:3:4:5:6:7:8:9", "1:2:3:4:5:6:7", "12345::",
  "1:2:3:4:5:6:7:", ":1:2:3:4:5:6:7", "::ffff:999.0.0.1", "", "x::1",
  0
};
int main(void) {
  int i;
  for (i = 0; cases[i]; i++) {
    unsigned char b[16]; char out[64]; int r; const char *o;
    memset(b, 0xee, sizeof b);
    errno = 0;
    r = inet_pton(AF_INET6, cases[i], b);
    printf("%-42s pton=%d", cases[i], r);
    if (r == 1) {
      int k; printf(" bin=");
      for (k = 0; k < 16; k++) printf("%02x", b[k]);
      o = inet_ntop(AF_INET6, b, out, sizeof out);
      printf(" ntop=%s", o ? o : "(null)");
    }
    printf("\n");
  }
  /* Small-buffer and bad-family behaviour: both are error paths a caller
     branches on, and both are silent if wrong. */
  {
    unsigned char b[16]; char small[4]; const char *o; int r, e;
    /* CALL, THEN READ errno, THEN PRINT. Putting the call and `errno' in one
       printf argument list reads errno BEFORE the call on gcc, which
       evaluates right to left -- the first draft of this probe did exactly
       that and reported errno=0 for glibc on every error path. Argument
       evaluation order is unspecified, so this is a probe bug in both
       compilers and it happened to be invisible in one. */
    inet_pton(AF_INET6, "2001:db8::1", b);
    errno = 0; o = inet_ntop(AF_INET6, b, small, sizeof small); e = errno;
    printf("small-buf ntop=%s errno=%d\n", o ? "SET" : "null", e);
    errno = 0; r = inet_pton(99, "1.2.3.4", b); e = errno;
    printf("bad-family pton=%d errno=%d\n", r, e);
    errno = 0; o = inet_ntop(99, b, small, sizeof small); e = errno;
    printf("bad-family ntop=%s errno=%d\n", o ? "SET" : "null", e);
  }
  return 0;
}
