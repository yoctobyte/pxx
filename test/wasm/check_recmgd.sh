#!/bin/sh
# ARC-correct whole-record copy on wasm32 — IR_COPY_REC_MANAGED.
#
# THE DIFF IS NOT ENOUGH HERE, and saying so is the point. A record copy with
# the retain/release omitted prints exactly the same thing as a correct one for
# as long as nothing has been freed yet: the bytes are copied either way. What
# differs is a refcount, and a refcount is only observable later and elsewhere —
# as a leak at one end and a use-after-free at the other. So this check carries
# three instruments, and the diff is the weakest of them:
#
#   * the DIFF, against the native build, for the values;
#   * an OUTLIVE row inside the slice: the source's fields are destroyed and
#     the copy read afterwards. A missed retain reads freed memory here, and
#     freed memory in this allocator reads as plausible data rather than as a
#     fault, which is why the row prints its contents rather than a flag;
#   * a LEAK PROBE below, which is the only thing that can see a missed
#     RELEASE at all.
#
# WHY THE LEAK PROBE LOOKS ODD. It assigns a FRESH owned value into the
# destination each iteration. An earlier version simply repeated `b := a` and
# was measured NOT to detect a missing release — flat at 1032 either way, in a
# build with the release deliberately removed. Repeating one assignment leaks a
# REFCOUNT, not an ALLOCATION, and the bump pointer cannot see a refcount. The
# destination has to own something new each time for failing to release it to
# cost memory. That negative result is recorded here because the probe reads
# like a formality and is not one: it was decoration until it was falsified.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-recmgd.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/recmgd_slice.pas" "$work/native" > /dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 "$here/recmgd_slice.pas" \
    "$work/s.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/s.wasm"

if grep -qE '^    (ShowVal|main\$0) ' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (ShowVal|main\$0) ' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

cat > "$work/run.js" <<'JS'
const fs = require('fs');
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
const sp0 = inst.exports.sp.value;
try { inst.exports.main(); } catch (e) { if (!(e instanceof h.HostExit)) throw e; }
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(h.text(1));
JS

node "$work/run.js" "$work/s.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines)"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

for row in \
  'assign  hello 3 7 3' \
  'self    hello 3 7' \
  'byval   hello 3 7' \
  'overw   hello 3' \
  'outlive hello 3 2' \
  'nested  nested 4 tag' \
  'elem    elem 5 5'
do
  grep -qxF "$row" "$work/wasm.txt" || { echo "FAIL missing row: $row"; exit 1; }
done
echo "ok  every row asserted individually:"
echo "..  plain assignment, self-assignment (the row that fails if retain and"
echo "..  release are swapped), a by-value parameter, overwriting a destination"
echo "..  that already owned something, a copy that OUTLIVES its source, a"
echo "..  managed field inside a nested record, and a copy into a heap element"

# --- the leak probe ---------------------------------------------------------
mkleak() { cat > "$work/leak.pas" <<EOF
program RecLeak;
type
  TRow = array of Integer;
  TR = record S: string; A: TRow; N: Integer; end;
var a, b: TR; i: Integer; p1, p2: Pointer;
begin
  a.S := 'hello'; SetLength(a.A, 3); a.N := 7;
  for i := 1 to 100 do begin SetLength(b.A, 5); b := a; end;
  p1 := PXXAlloc(1024, 8);
  for i := 1 to $1 do begin SetLength(b.A, 5); b := a; end;
  p2 := PXXAlloc(1024, 8);
  writeln(NativeInt(p2) - NativeInt(p1));
end.
EOF
}
leakrun() {
  mkleak "$1"
  "$root/compiler/pascal26" --target=wasm32 "$work/leak.pas" "$work/leak.wasm" \
      > /dev/null 2>&1
  node "$work/run.js" "$work/leak.wasm"
}
a1=$(leakrun 1000)
a2=$(leakrun 9000)
if [ "$a1" != "$a2" ]; then
  echo "FAIL a record copy does not release the destination's old references:"
  echo "     1000 iterations advance the heap by $a1 bytes and 9000 by $a2. A"
  echo "     build with the release removed was measured at 18392 and 2712 for"
  echo "     the same two counts, so this is what that failure looks like."
  exit 1
fi
echo "ok  1000 and 9000 iterations both advance the heap by $a1 bytes — the"
echo "..  destination's old references are released on every copy"

# The oracle half, for the same reason check_strop carries one: two builds that
# are each self-consistent can still disagree about a constant, and a slope test
# cannot see that.
mkleak 1000
"$root/compiler/pascal26" "$work/leak.pas" "$work/leakn" > /dev/null
n1=$("$work/leakn")
mkleak 9000
"$root/compiler/pascal26" "$work/leak.pas" "$work/leakn" > /dev/null
n2=$("$work/leakn")
if [ "$n1" != "$n2" ]; then
  echo "FAIL the NATIVE build leaks a record copy: $n1 at 1000, $n2 at 9000."
  echo "     The bug is not wasm's; check x86-64's IR_COPY_REC_MANAGED arm."
  exit 1
fi
if [ "$n1" != "$a1" ]; then
  echo "FAIL the two builds disagree about the advance: native $n1, wasm $a1."
  echo "     Both flat, so neither leaks per-copy, but one allocates a different"
  echo "     fixed amount for the same program."
  exit 1
fi
echo "ok  native is flat at $n1 too and the two agree exactly"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/recmgd_slice.pas" \
   "$work" s

# --- what this check does NOT catch -----------------------------------------
#  * a FUNCTION returning a managed record. It refuses upstream of this op with
#    `EmitZeroFrameSlot: unhandled target` — the loud arm of the Track A ticket
#    bug-a-emitzeroframeslot-has-no-wasm32-arm — so the path where a callee
#    builds a managed record and copies it out through the hidden destination is
#    untested on this target. Named in the slice too, at the top.
#  * a record with a COM INTERFACE field. The interface half of the walk
#    (PXXRecordRetainIntf / ReleaseIntf) is emitted and never exercised here:
#    nothing in this slice declares one. That half is where the register
#    backends had their lock-order bug, so its being untested is worth knowing.
#  * a VARIANT or a NilPy class-typed field — kinds 5 and 6 of the RTL's walk.
#  * a record copied under an exception unwind, where the release runs from the
#    handler rather than in line.
echo "PASS check_recmgd"
