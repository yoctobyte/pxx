#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Count occurrences of a literal byte sequence in a file.

WHY THIS EXISTS. The compiler's own `code=` summary is PAGE-QUANTISED (4096
here), so it reports a delta of zero for a change that rewrites every prologue
in the image, and a delta of 4096 for one that added 1944 bytes. When a test
needs to assert that a particular INSTRUCTION SEQUENCE is present -- that the
long form of a call or a jump actually fired, rather than that the program
merely ran -- the artifact is the only honest source, and a shell cannot count a
binary pattern containing NUL (`grep -P '\\x00'` silently matches nothing).

Typical use is a POSITIVE CONTROL in a Makefile row: a test for an out-of-range
jump stops exercising the wall the moment the generated body falls back under
the limit, and passes forever afterwards while covering nothing.

    tools/count_bytes.py <file> <hex-bytes> [--expect N] [--min N]

    tools/count_bytes.py out a0998 0a00900 --expect 1

Hex may contain spaces; --expect requires exactly N, --min at least N. Without
either it prints the count and exits 0.
"""
import sys


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    path, hexpat = argv[1], argv[2]
    want_exact = want_min = None
    i = 3
    while i < len(argv):
        if argv[i] == '--expect':
            want_exact = int(argv[i + 1]); i += 2
        elif argv[i] == '--min':
            want_min = int(argv[i + 1]); i += 2
        else:
            print('count_bytes: unknown argument %s' % argv[i], file=sys.stderr)
            return 2
    try:
        pat = bytes.fromhex(hexpat.replace(' ', ''))
    except ValueError as e:
        print('count_bytes: bad hex %r (%s)' % (hexpat, e), file=sys.stderr)
        return 2
    if not pat:
        print('count_bytes: empty pattern', file=sys.stderr)
        return 2
    with open(path, 'rb') as f:
        data = f.read()
    n, at = 0, data.find(pat)
    while at >= 0:
        n += 1
        at = data.find(pat, at + 1)
    if want_exact is not None and n != want_exact:
        print('count_bytes: %s has %d occurrences of %s, expected %d'
              % (path, n, pat.hex(), want_exact), file=sys.stderr)
        return 1
    if want_min is not None and n < want_min:
        print('count_bytes: %s has %d occurrences of %s, expected at least %d'
              % (path, n, pat.hex(), want_min), file=sys.stderr)
        return 1
    print(n)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
