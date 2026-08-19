"""Check lib_strtofloat_lemire's output against CPython's own float().

Reads `<decimal-string> <parsed-bits-hex>` lines on stdin and compares each
parsed bit pattern with the one CPython produces for the identical string.
Both are meant to be correctly rounded, so ANY difference is a real defect in
one of them — and CPython's float parser is the one with a few billion users.

Exits nonzero on the first mismatch after printing a handful, so a broken
power-of-ten table names the exact inputs that expose it rather than just
failing a count.
"""

import struct
import sys


def bits_of(x):
    return struct.unpack("<Q", struct.pack("<d", x))[0]


def main():
    checked = 0
    bad = 0
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        text, got_hex = line.rsplit(" ", 1)
        checked += 1
        want = bits_of(float(text))
        got = int(got_hex, 16)
        if want != got:
            bad += 1
            if bad <= 10:
                print("MISMATCH %s: cpython=%016X pxx=%016X" % (text, want, got))
    if checked == 0:
        print("FAIL: no values to check")
        return 1
    if bad:
        print("FAIL: %d of %d parses differ from CPython" % (bad, checked))
        return 1
    print("  lib-test: StrToFloat matches CPython on %d values" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
