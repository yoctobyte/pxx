/* SPDX-License-Identifier: Zlib */
/* strerror over the whole Linux errno range, diffed against gcc.

   THE RANGE IS THE POINT. src/string.c's table covers 0..133 -- EHWPOISON
   included -- and its own comment claimed "0..40" long after that stopped
   being true, which is the kind of stale sentence that talks the next reader
   out of relying on something that works.

   IT BECAME LOAD-BEARING ON 2026-09-04. <errno.h> carried only 71 of the 133
   names until then, and an undefined errno name is not a compile error here:
   pxx substitutes 0. So ENODATA and ENOTRECOVERABLE were unreachable AND
   untestable, and `errno == ENODATA' was true exactly when nothing had gone
   wrong. With the names present those are real values that real programs
   report, and this row is what they print as.

   134 is one past the end on purpose: it must fall into the "Unknown error N"
   branch and match glibc's wording there too, so the table's END is asserted
   and not just its contents. */
#include <stdio.h>
#include <string.h>
int main(void) { int i; for (i = 0; i <= 134; i++) printf("%d %s\n", i, strerror(i)); return 0; }
