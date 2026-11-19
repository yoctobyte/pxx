#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Input for test_val_float_correctly_rounded.pas: one `repr(d) HEXBITS` per line.

6000 doubles from a uniform spread of decimal exponents in [-320, 308] (the
ticket's sample shape, so subnormals are in it), plus the fixed extremes.
Seeded, so a failure reproduces. CPython's repr() is the shortest string that
reads back as d, and float() is correctly rounded, so `Val(repr(d)) = d` on the
BITS is exactly the property: a printed comparison cannot see a last-place
miss. bug-b-val-of-a-float-is-not-correctly-rounded-while-strtofloat-of-the-same-string-is
"""
import random
import struct
import sys


def bits(d):
    return struct.unpack("<Q", struct.pack("<d", d))[0]


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 6000
    rnd = random.Random(20260910)
    fixed = [5e-324, 2.2250738585072014e-308, 2.225073858507201e-308,
             1.7976931348623157e+308, 0.1, 1 / 3, 1e-300, 1e22, 1e23,
             9007199254740993.0, 123456789012345678.0, 0.0, -0.0]
    vals = list(fixed)
    while len(vals) < n:
        e = rnd.randint(-320, 308)
        d = float("%.17ge%d" % (rnd.random() * 9 + 1, e))
        if d != d or d in (float("inf"), float("-inf")):
            continue
        if rnd.random() < 0.5:
            d = -d
        vals.append(d)
    for d in vals:
        print("%s %016X" % (repr(d), bits(d)))


if __name__ == "__main__":
    main()
