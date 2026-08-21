#!/usr/bin/env python3
"""Generate a C program with N DISTINCT string literals.

The point is the count, not the program: it exists to hold MAX_STRS above the
literal count a real generated program reaches. csmith --paranoid emits an
assertion carrying its own message text at every pointer operation, so its
literal count scales with the program rather than staying flat the way
hand-written C does — seed 200056 (14125 lines) reached 9426 distinct literals
and was refused with `string table overflow`.

bug-a-string-table-cap-refuses-a-14k-line-c-program
"""
import sys

n = int(sys.argv[1])
out = sys.argv[2]
b = ['#include <stdio.h>', 'int main(void){', '  unsigned long h=0;']
b += ['  h += (unsigned long)"lit-%d-distinct-payload"[0] + %d;' % (i, i)
      for i in range(n)]
# putchar over an escape in printf: the generated source stays free of
# backslashes, which have to survive make + shell + python quoting otherwise.
b += ['  printf("%lu", h);', '  putchar(10);', '  return 0;', '}']
open(out, 'w').write('\n'.join(b) + '\n')
