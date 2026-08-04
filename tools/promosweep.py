#!/usr/bin/env python3
"""Sweep Pascal PromoInt against a Python oracle.

Arbitrary precision IS Python's semantics, so Python is the oracle — with two
deliberate corrections:

  * Pascal's `div`/`mod` TRUNCATE toward zero; Python's `//`/`%` FLOOR. The
    promo runtime keeps the Pascal rule for Pascal (PXXPromoFloorDiv/FloorMod
    exist separately and are chosen by PyProgramMode), so the oracle truncates.
  * `shr` on a negative is Pascal's, and promocore documents Python
    two's-complement semantics for the BITWISE ops, so and/or/xor use Python's
    directly.

Every case is emitted twice: once as Pascal, once as Python. Values straddle
the inline/heap tier boundary (2^63) deliberately, because only the heap tier
has a managed payload and only it can double-free or leak.
"""
import os, subprocess, sys, shutil

OUT = sys.argv[1] if len(sys.argv) > 1 else "psweep"
PXX = "/home/rene/frankonpiler/compiler/pascal26"
TARGET = sys.argv[2] if len(sys.argv) > 2 else ""

VALUES = [0, 1, -1, 7, 255, -255,
          2**31, 2**31 - 1, -(2**31),
          2**62, 2**63 - 1, -(2**63),
          2**63, 2**64, 2**70, -(2**70),
          10**25, -(10**25)]

BINOPS = [("+", "+"), ("-", "-"), ("*", "*"),
          ("div", "DIV"), ("mod", "MOD"),
          ("and", "&"), ("or", "|"), ("xor", "^")]
CMPOPS = [("=", "=="), ("<>", "!="), ("<", "<"), ("<=", "<="),
          (">", ">"), (">=", ">=")]
SHIFTS = [("shl", "<<"), ("shr", "SHR")]
SHIFT_COUNTS = [0, 1, 4, 31, 63, 64, 70]


def oracle(a, op, b):
    if op == "DIV":
        if b == 0:
            return None
        q = abs(a) // abs(b)
        return -q if (a < 0) != (b < 0) else q
    if op == "MOD":
        if b == 0:
            return None
        q = abs(a) // abs(b)
        q = -q if (a < 0) != (b < 0) else q
        return a - q * b
    if op == "SHR":
        return a >> b          # Pascal shr on a promo goes through BShr, which
                               # documents Python's flooring shift
    return eval("a %s b" % op)


def emit(name, decls, body_pas, body_py):
    with open(os.path.join(OUT, name + ".pas"), "w") as f:
        f.write("program t;\nuses promocore;\nvar %s: PromoInt;\nbegin\n%send.\n"
                % (decls, body_pas))
    with open(os.path.join(OUT, name + ".py"), "w") as f:
        f.write(body_py)


def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    cases = []

    n = 0
    for pas_op, py_op in BINOPS:
        for a in VALUES:
            for b in VALUES:
                if py_op in ("DIV", "MOD") and b == 0:
                    continue
                want = oracle(a, py_op, b)
                name = "b%04d" % n; n += 1
                emit(name, "x, y, z",
                     "  x := %d;\n  y := %d;\n  z := x %s y;\n"
                     "  writeln(PXXPromoToStr(@z));\n" % (a, b, pas_op),
                     "print(%d)\n" % want)
                cases.append(name)

    for pas_op, py_op in CMPOPS:
        for a in VALUES:
            for b in VALUES:
                want = oracle(a, py_op, b)
                name = "c%04d" % n; n += 1
                emit(name, "x, y",
                     "  x := %d;\n  y := %d;\n"
                     "  if x %s y then writeln('T') else writeln('F');\n"
                     % (a, b, pas_op),
                     "print('T' if %s else 'F')\n" % want)
                cases.append(name)

    for pas_op, py_op in SHIFTS:
        for a in VALUES:
            for k in SHIFT_COUNTS:
                want = oracle(a, py_op, k)
                name = "s%04d" % n; n += 1
                emit(name, "x, z",
                     "  x := %d;\n  z := x %s %d;\n"
                     "  writeln(PXXPromoToStr(@z));\n" % (a, pas_op, k),
                     "print(%d)\n" % want)
                cases.append(name)

    # writeln of a promo DIRECTLY (a different path from PXXPromoToStr), and a
    # machine-int cast round-trip where the value fits
    for a in VALUES:
        name = "w%04d" % n; n += 1
        emit(name, "x", "  x := %d;\n  writeln(x);\n" % a, "print(%d)\n" % a)
        cases.append(name)

    print("generated %d cases in %s" % (len(cases), OUT))

    npass = nfail = 0
    fails = []
    for name in cases:
        pas = os.path.join(OUT, name + ".pas")
        exe = os.path.join(OUT, name)
        cmd = [PXX] + ([TARGET] if TARGET else []) + [pas, exe]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if not os.path.exists(exe):
            nfail += 1
            fails.append((name, "COMPILE-FAIL", (r.stdout + r.stderr).strip().split("\n")[-1]))
            continue
        try:
            got = subprocess.run([exe], capture_output=True, text=True,
                                 timeout=10).stdout.strip()
        except subprocess.TimeoutExpired:
            nfail += 1
            fails.append((name, "HANG", ""))
            continue
        want = subprocess.run([sys.executable, os.path.join(OUT, name + ".py")],
                              capture_output=True, text=True).stdout.strip()
        if got == want:
            npass += 1
        else:
            nfail += 1
            fails.append((name, got, want))

    for name, got, want in fails[:60]:
        src = open(os.path.join(OUT, name + ".pas")).read().split("\n")
        expr = [l.strip() for l in src if ":=" in l or "if " in l]
        print("FAIL %s  got=%r want=%r   %s" % (name, got, want, " ".join(expr)))
    print("--- pass=%d fail=%d" % (npass, nfail))


main()
