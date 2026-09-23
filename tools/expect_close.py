#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
#
# expect_close.py — assert two outputs agree, with a ULP TOLERANCE on floats
# and NO tolerance on anything else.
#
#   tools/expect_close.py <label> <tol_ulp> <actual> <expected>
#   tools/expect_close.py --selftest
#
# Exit 0 when they agree, printing nothing. On disagreement, print a labelled
# diff of only the offending rows and exit 1.
#
# WHY THIS EXISTS
# ---------------
# tools/expect_same.sh compares two outputs byte for byte, which is the right
# instrument for bytes, strings and integers and the WRONG one for a float that
# a fast kernel produced. The owner settled the contract on 2026-09-22, on the
# ArcTan fast arm specifically: "yes, performance. screw insignificant bits
# pls. we learned our lesson." A last-place digit is not a defect, and a test
# that reddens on one costs a suite.
#
# Measured 2026-09-23 on test_nilpy_math_atan_and_atan2_bit_for_bit.npy at
# 2702b4abebca: 272 lines / 665 tokens / 657 parsed as float, of which 20
# differed from CPython and EVERY ONE of the 20 was exactly 1 ulp.
#
# WHY THE TOLERANCE IS 2 AND NOT A NUMBER I LIKED
# -----------------------------------------------
# It is not a new number. test/lib_math_fast_tolerance.pas already states the
# contract for these same fast kernels — "ACCURACY is a TOLERANCE. Within 2 ulp
# of glibc, and that is all" — and 6b8b45af45d9 measured the ArcTan kernel at
# max 1 ulp over ~15600 rows against glibc, 0 rows past 2. So 2 is the ratified
# figure for this code path and it leaves one ulp of headroom above what is
# measured: a gate born at its own limit reddens on the next legitimate
# last-bit change.
#
# WHAT GETS NO TOLERANCE, AND THIS IS THE HALF THAT MATTERS
# ---------------------------------------------------------
# A tolerance is for ACCURACY. It must not silently buy BEHAVIOUR, so every one
# of these is still compared exactly:
#
#   - any token whose text is already equal (integers, byte strings, labels)
#   - any token that is not a float in BOTH outputs
#   - nan and inf: a nan facing a number is a mismatch at any tolerance. This
#     is what keeps the subject file's own positive control alive — its first
#     five rows exist because ArcTan answered nan above the Dekker-split
#     threshold where CPython answers pi/2, and no ulp count can excuse that.
#   - THE SIGN BIT, including on zero. +0.0 against -0.0 is zero ulp apart
#     under the standard monotone mapping, so a bare ulp check would MASK
#     exactly the signed-zero defect the subject file says it is watching for
#     (see its DELIBERATELY ABSENT note). Sign is behaviour; it is compared
#     before the distance is.
#   - the line count, and the token count within a line.
#
# So the only thing this is softer about than expect_same.sh is the last couple
# of bits of a float that both sides agree is a finite float of the same sign.
#
# THE POSITIVE CONTROL IS BUILT IN
# --------------------------------
# --selftest asserts the rejections above, because a comparator that cannot
# fail is not a comparator. It is wired into the Makefile as its own row, so
# the instrument is proven able to say no in the same run that trusts it to say
# yes.

import struct
import sys


def _bits(x):
    return struct.unpack('>q', struct.pack('>d', x))[0]


def _ulps_apart(a, b):
    """Monotone-bit-pattern distance. Callers must have ruled out nan/inf and a
    sign difference first — this collapses +0.0 and -0.0, which is precisely
    why the sign check does not live in here."""
    ia, ib = _bits(a), _bits(b)
    if ia < 0:
        ia = -0x8000000000000000 - ia
    if ib < 0:
        ib = -0x8000000000000000 - ib
    return abs(ia - ib)


def _signbit(x):
    return _bits(x) < 0


def compare_token(got, want, tol):
    """Return None when the pair is acceptable, else a reason string."""
    if got == want:
        return None
    try:
        fg, fw = float(got), float(want)
    except ValueError:
        return "not a float on both sides"
    # nan never equals itself, so it can only arrive here; any nan/inf pair that
    # was genuinely identical was already let through by the text comparison.
    if fg != fg or fw != fw:
        return "nan mismatch"
    if fg in (float('inf'), float('-inf')) or fw in (float('inf'), float('-inf')):
        return "inf mismatch"
    if _signbit(fg) != _signbit(fw):
        return "sign differs"
    d = _ulps_apart(fg, fw)
    if d > tol:
        return "%d ulp apart (tolerance %d)" % (d, tol)
    return None


def compare(actual, expected, tol):
    """Return a list of human-readable complaints; empty means agreement."""
    a_lines, e_lines = actual.splitlines(), expected.splitlines()
    out = []
    if len(a_lines) != len(e_lines):
        out.append("line count differs: actual %d, expected %d"
                   % (len(a_lines), len(e_lines)))
    for n, (el, al) in enumerate(zip(e_lines, a_lines), 1):
        if el == al:
            continue
        et, at = el.split(), al.split()
        if len(et) != len(at):
            out.append("line %d: token count differs\n  expected: %s\n    actual: %s"
                       % (n, el, al))
            continue
        for eg, ag in zip(et, at):
            why = compare_token(ag, eg, tol)
            if why:
                out.append("line %d: %s\n  expected: %s\n    actual: %s"
                           % (n, why, el, al))
                break
    return out


def selftest():
    """Every row here is a REJECTION the comparator must produce, except the
    two marked accept. Drawn from the population this tool is pointed at: the
    values are the subject file's own special cases."""
    tol = 2
    must_reject = [
        ("nan",   "1.5707963267948966", "nan facing pi/2 — the subject's own positive control"),
        ("1.5707963267948966", "nan",   "number facing nan"),
        ("0.0",   "-0.0",               "signed zero, which is 0 ulp apart"),
        ("-0.0",  "0.0",                "signed zero, the other way"),
        ("1.0",   "-1.0",               "sign flip"),
        ("inf",   "1.7976931348623157e308", "inf facing a finite"),
        ("1.0000000000000007", "1.0",   "3 ulp, one past tolerance"),
        ("2.0",   "1.0",                "wholly wrong value"),
        ("b'\\x3f\\xd0'", "b'\\x3f\\xd1'", "raw bytes differ"),
        ("3",     "4",                  "integers differ"),
    ]
    must_accept = [
        ("1.0738277219158432", "1.0738277219158434", "1 ulp — the measured case"),
        ("1.0000000000000004", "1.0",   "2 ulp — exactly at tolerance"),
        ("nan",   "nan",                "nan text matching nan"),
        ("-0.0",  "-0.0",               "signed zero matching itself"),
    ]
    bad = 0
    for got, want, why in must_reject:
        if compare_token(got, want, tol) is None:
            print("SELFTEST FAIL: accepted %r vs %r — %s" % (got, want, why))
            bad += 1
    for got, want, why in must_accept:
        r = compare_token(got, want, tol)
        if r is not None:
            print("SELFTEST FAIL: rejected %r vs %r (%s) — %s" % (got, want, r, why))
            bad += 1
    # structural rejections
    if not compare("a\nb", "a", tol):
        print("SELFTEST FAIL: accepted a line-count difference")
        bad += 1
    if not compare("1.0 2.0", "1.0", tol):
        print("SELFTEST FAIL: accepted a token-count difference")
        bad += 1
    if compare("1.0 nan -0.0", "1.0 nan -0.0", tol):
        print("SELFTEST FAIL: rejected two identical outputs")
        bad += 1
    if bad:
        print("expect_close selftest: %d FAILED" % bad)
        return 1
    print("expect_close selftest: ok")
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        return selftest()
    if len(argv) != 5:
        print("expect_close.py: usage: expect_close.py <label> <tol_ulp> "
              "<actual> <expected>", file=sys.stderr)
        print("                        expect_close.py --selftest", file=sys.stderr)
        return 2
    label, tol, actual, expected = argv[1], argv[2], argv[3], argv[4]
    try:
        tol = int(tol)
    except ValueError:
        print("expect_close.py: tolerance must be an integer, got %r" % tol,
              file=sys.stderr)
        return 2

    # Carried over from expect_same.sh: two empty operands compare equal, which
    # is also what a subject that silently produced nothing looks like. We keep
    # the verdict and refuse to be silent about it.
    if not actual and not expected:
        print("expect_close: WARNING [%s]: both operands are EMPTY — this "
              "passes, but a subject that produced nothing looks exactly like "
              "this. Check that the command under test ran." % label,
              file=sys.stderr)
        return 0

    problems = compare(actual, expected, tol)
    if not problems:
        return 0
    print("expect_close: MISMATCH [%s] (tolerance %d ulp on floats; "
          "everything else exact)" % (label, tol))
    for p in problems[:40]:
        print(p)
    if len(problems) > 40:
        print("... and %d more" % (len(problems) - 40))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
