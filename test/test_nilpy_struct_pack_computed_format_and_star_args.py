# Regression test for bug-n-struct-pack-with-a-computed-format-and-star-args-raises-typeerror
# (closed 2026-11-10: it passes at latest; expected = python3).
import struct


def k(n):
    vals = [0.0, 0.5, 1.0]
    return len(struct.pack("<%df" % n, *vals))


print(k(3))
