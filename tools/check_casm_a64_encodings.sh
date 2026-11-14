#!/bin/sh
# check_casm_a64_encodings.sh <compiler> <workprefix>
#
# The aarch64 inline-asm encoder (compiler/casm_a64.inc) against llvm-mc.
# Every line of test/casm_a64_encodings.s goes into ONE operand-less
# __asm__ statement, so pxx's words for them are contiguous in the object;
# that run must equal llvm-mc's encoding of the same lines, byte for byte.
# Skips (exit 0, says so) when no llvm-mc is installed.
set -u
PXX=$1; W=$2
MC=""
for c in llvm-mc llvm-mc-21 llvm-mc-20 llvm-mc-19 llvm-mc-18; do
  if command -v "$c" > /dev/null 2>&1; then MC=$c; break; fi
done
[ -n "$MC" ] || { echo "check_casm_a64_encodings: SKIP (no llvm-mc)"; exit 0; }
exec python3 -I - "$PXX" "$W" "$MC" test/casm_a64_encodings.s <<'PY'
import re, subprocess, sys
pxx, w, mc, src = sys.argv[1:5]
lines = [l.strip() for l in open(src) if l.strip() and not l.strip().startswith("//")]
r = subprocess.run([mc, "-triple=aarch64", "-show-encoding"], input="\n".join(lines) + "\n",
                   capture_output=True, text=True)
if r.returncode != 0:
    sys.exit("check_casm_a64_encodings: FAIL: llvm-mc refused the file:\n" + r.stderr)
enc = [bytes(int(b, 16) for b in m.split(","))
       for m in re.findall(r"encoding: \[([0-9a-fx,]+)\]", r.stdout)]
if len(enc) != len(lines):
    sys.exit("check_casm_a64_encodings: FAIL: llvm-mc gave %d encodings for %d lines" % (len(enc), len(lines)))
body = "\\n".join(lines)
open(w + "_a64enc.c", "w").write('void casm_a64_encodings(void) { __asm__ volatile ("%s"); }\n' % body)
r = subprocess.run([pxx, "--target=aarch64", "--emit-obj", w + "_a64enc.c", w + "_a64enc.o"],
                   capture_output=True, text=True)
if r.returncode != 0:
    sys.exit("check_casm_a64_encodings: FAIL: pxx refused the block:\n" + r.stdout + r.stderr)
obj = open(w + "_a64enc.o", "rb").read()
want = b"".join(enc)
at = obj.find(want)
if at >= 0:
    print("check_casm_a64_encodings: OK (%d instructions)" % len(lines))
    sys.exit(0)
# find the first word that differs: anchor on the first instruction
at = obj.find(enc[0])
if at < 0:
    sys.exit("check_casm_a64_encodings: FAIL: even the first instruction (%s) is not in the object" % lines[0])
for i, e in enumerate(enc):
    got = obj[at + 4 * i: at + 4 * i + 4]
    if got != e:
        sys.exit("check_casm_a64_encodings: FAIL: %r: pxx %s, llvm-mc %s" % (lines[i], got.hex(), e.hex()))
sys.exit("check_casm_a64_encodings: FAIL: no difference found, but no match either")
PY
