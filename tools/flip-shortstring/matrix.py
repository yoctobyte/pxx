#!/usr/bin/env python3
"""The phase-4 shortstring flip: seven targets x two modes, plus the FPC oracle.

-dPXX_SHORTSTRING today IS the post-flip default, so "off" is the tree as it
stands and "on" is what the flip hands everyone. Both only coexist until the
flag is deleted, which is why this had to run before it goes.

Verdicts per (test, target):
  SAME            off and on produce the same bytes and the same rc
  OUTPUT-DIFFERS  same rc, different bytes  -- the flip changed the answer
  RC-DIFFERS      different rc              -- the flip changed whether it runs
  BUILD-*-FAIL    one mode does not compile for that target

The FPC column applies to the NATIVE row only (FPC 3.2.2, x86-64):
  =OFF  the oracle matches today's output   -> the flip REGRESSES this row
  =ON   the oracle matches the flip's       -> the flip FIXES this row
  =BOTH off and on agree and match FPC
  !BOTH neither matches FPC (pre-existing; not the flip's doing)
  n/a   FPC cannot build it (pxx dialect, pxx-only unit, pxx intrinsic)
"""
import os, re, sys

S = sys.argv[1]
D = os.path.join(S, "x")
F = os.path.join(S, "f")
TARGETS = ["x86_64", "i386", "aarch64", "arm32", "riscv32", "xtensa", "wasm32"]

# THREE NORMALISATIONS, each measured to be the INSTRUMENT and not the flip.
#  1. the binary's own path -- wasmtime prints `failed to run main module
#     <path>` on a trap, and the two modes are two different files, so every
#     trapping wasm32 row came back OUTPUT-DIFFERS with identical rcs. 12 rows.
#  2. the code offsets in a wasmtime trap BACKTRACE -- `0x10fb8 - <unknown>!
#     <wasm function 145>`. Same trap, same functions, offsets shifted because
#     the code changed size. Scoped to backtrace lines only, so a program that
#     legitimately prints a hex number is untouched. 3 rows.
#  3. NOT normalised, EXCLUDED, and named: i386 test_rtti_reg dumps raw RTTI
#     containing a STACK ADDRESS. Running the SAME binary twice changes 3 of
#     47557 bytes, so ASLR alone produced a per-target "finding". Every
#     differing row was re-measured against itself (flip/noise.sh); that one is
#     the only NOISE-OUTPUT, the other 32 are STABLE.
NOISE_ROWS = {("test_rtti_reg", "i386")}
_WASM_TRACE = re.compile(r"0x[0-9a-f]+(?=\s+-\s+<unknown>!<wasm function)")

def norm(path, text):
    base = os.path.basename(path)
    text = text.replace(path, "<BIN>").replace(
        base, base.replace(".off", ".MODE").replace(".on", ".MODE"))
    return _WASM_TRACE.sub("0xNNN", text)

def read(p):
    try:
        return open(p, errors="replace").read()
    except OSError:
        return None

verdict = {}
tests = []
for t in TARGETS:
    tsv = os.path.join(S, t + ".tsv")
    if not os.path.exists(tsv):
        continue
    for line in open(tsv):
        line = line.rstrip("\n")
        if not line or line.startswith("DONE"):
            continue
        parts = line.split("\t")
        b, v = parts[0], parts[1]
        if b not in tests:
            tests.append(b)
        if v in ("SAME", "OUTPUT-DIFFERS"):
            ext = ".wasm" if t == "wasm32" else ""
            offp = os.path.join(D, "%s.%s.off%s" % (t, b, ext))
            onp = os.path.join(D, "%s.%s.on%s" % (t, b, ext))
            o, n = read(offp + ".out"), read(onp + ".out")
            if o is None or n is None:
                v = "NO-OUTPUT"
            else:
                v = "SAME" if norm(offp, o) == norm(onp, n) else "OUTPUT-DIFFERS"
                if (b, t) in NOISE_ROWS and v == "OUTPUT-DIFFERS":
                    v = "NOISE"
        verdict[(b, t)] = (v, parts[2] if len(parts) > 2 else "")

def fpc_verdict(b):
    fo = read(os.path.join(F, "fpc.%s" % b, "%s.fpc.out" % b))
    if fo is None:
        return "n/a"
    offp = os.path.join(D, "x86_64.%s.off" % b)
    onp = os.path.join(D, "x86_64.%s.on" % b)
    o, n = read(offp + ".out"), read(onp + ".out")
    if o is None or n is None:
        return "n/a"
    o, n = norm(offp, o), norm(onp, n)
    mo, mn = (o == fo), (n == fo)
    if mo and mn: return "=BOTH"
    if mo: return "=OFF"
    if mn: return "=ON"
    return "!BOTH"

SHORT = {"SAME": ".", "OUTPUT-DIFFERS": "OUT", "RC-DIFFERS": "RC",
         "BUILD-OFF-FAIL": "b-", "BUILD-ON-FAIL": "-b", "NO-OUTPUT": "?",
         "NOISE": "~"}

print("%-48s %s  %s" % ("test", " ".join("%-4s" % t[:4] for t in TARGETS), "FPC"))
interesting = []
for b in sorted(tests):
    row = [SHORT.get(verdict.get((b, t), ("--", ""))[0], verdict.get((b, t), ("--", ""))[0])
           for t in TARGETS]
    fv = fpc_verdict(b)
    if set(row) <= {".", "--"} and fv in ("=BOTH", "n/a"):
        continue
    interesting.append(b)
    print("%-48s %s  %s" % (b, " ".join("%-4s" % c for c in row), fv))

print()
print("rows where the flip changes NOTHING on any target and FPC agrees: %d of %d"
      % (len(tests) - len(interesting), len(tests)))
for t in TARGETS:
    tally = {}
    for b in tests:
        v = verdict.get((b, t), ("(not swept)", ""))[0]
        tally[v] = tally.get(v, 0) + 1
    print("%-8s %s" % (t, "  ".join("%s=%d" % kv for kv in sorted(tally.items()))))
