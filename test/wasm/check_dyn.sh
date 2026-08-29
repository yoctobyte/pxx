#!/bin/sh
# Dynamic arrays on wasm32 — the layout, the aliasing, and the refcount.
#
# THE ORACLE IS THE NATIVE BUILD for everything the output can show, and an
# ARENA SLOPE for the one thing it cannot. A refcount is invisible in a diff:
# a build that shares without retaining prints exactly what a correct one
# prints, right up until it frees a block something still holds. Measured
# before this slice landed: 10512 bytes per 1000 iterations where native was
# flat at 1032, and at 9000 iterations the module exhausted linear memory.
#
# TWO leak probes, not one, and that is the point of the pair. The store's
# release (`b := a` drops b's old block) and the scope-exit release (a local
# array dies with its frame) are different mechanisms in different procedures.
# One probe exercising both would go red for either, which is one assertion
# wearing two names — a break in either mechanism would look identical and the
# second would be untested. Probe A has no local arrays; probe B has no
# assignments between arrays.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-dyn.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/dyn_slice.pas" "$work/native" > /dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 "$here/dyn_slice.pas" "$work/d.wasm" \
    > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/d.wasm"

if grep -qE '^    (Local|main\$[0-9])' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Local|main\$[0-9])' "$work/cov.txt"
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

node "$work/run.js" "$work/d.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  unset Length, fill, shrink keeping the head, grow zero-filling the"
  echo "..  tail, aliasing visible through both names, SetLength on one alias,"
  echo "..  length zero, a variable index, and an array of managed elements;"
  echo "..  \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# --- SetLength must get the SLOT, not the handle ----------------------------
# PXXDynSetLen takes `arrSlot = nil` as "nothing to do". Handing it the handle
# of a fresh (nil) array therefore SUCCEEDS and allocates nothing, and the
# assertion that catches it is a length read back after the call — not the
# presence of the call, which is there either way.
cat > "$work/slot.pas" <<'EOF'
program Slot;
var a: array of Integer;
begin
  SetLength(a, 3);
  writeln('len=', Length(a));
end.
EOF
"$root/compiler/pascal26" --target=wasm32 "$work/slot.pas" "$work/slot.wasm" \
    > /dev/null 2>&1
got=$(node "$work/run.js" "$work/slot.wasm")
if [ "$got" != "len=3" ]; then
  echo "FAIL SetLength on a fresh array did not allocate — got [$got]."
  echo "     PXXDynSetLen was handed the HANDLE (nil) instead of the SLOT, so"
  echo "     it took its nothing-to-do exit and reported success."
  exit 1
fi
echo "ok  SetLength on a fresh array allocates — it is handed the slot, and a"
echo "..  build handed the handle would report success and allocate nothing"

# --- leak probe A: ASSIGNMENT between arrays, no local arrays ----------------
probeA() { cat > "$work/leakA.pas" <<EOF
program LeakA;
var i: Integer; a, b: array of Integer; p1, p2: Pointer;
begin
  for i := 1 to 100 do begin SetLength(a, 8); b := a; SetLength(b, 3); end;
  p1 := PXXAlloc(1024, 8);
  for i := 1 to $1 do begin SetLength(a, 8); b := a; SetLength(b, 3); end;
  p2 := PXXAlloc(1024, 8);
  writeln(NativeInt(p2) - NativeInt(p1));
end.
EOF
}
# --- leak probe B: a LOCAL array dying with its frame, no assignments --------
probeB() { cat > "$work/leakB.pas" <<EOF
program LeakB;
var i: Integer; p1, p2: Pointer;
procedure Use;
var t: array of Integer;
begin
  SetLength(t, 8); t[0] := 1;
end;
begin
  for i := 1 to 100 do Use;
  p1 := PXXAlloc(1024, 8);
  for i := 1 to $1 do Use;
  p2 := PXXAlloc(1024, 8);
  writeln(NativeInt(p2) - NativeInt(p1));
end.
EOF
}
run_probe() {   # $1 = probe fn, $2 = iterations, $3 = target flags
  $1 "$2"
  src=$(echo "$1" | sed 's/probe/leak/')
  "$root/compiler/pascal26" $3 "$work/$src.pas" "$work/$src.out" >/dev/null 2>&1
  if [ -n "$3" ]; then node "$work/run.js" "$work/$src.out"; else "$work/$src.out"; fi
}
for probe in probeA probeB; do
  case $probe in
    probeA) what="an assignment between arrays (the store's release)";;
    probeB) what="a local array dying with its frame (scope-exit release)";;
  esac
  w1=$(run_probe $probe 1000 "--target=wasm32")
  w2=$(run_probe $probe 9000 "--target=wasm32")
  if [ "$w1" != "$w2" ]; then
    echo "FAIL $what leaks: 1000 iterations advance the heap by $w1 bytes and"
    echo "     9000 by $w2. A dynamic array is shared by handle, so a missing"
    echo "     retain or release is invisible in the output and visible only"
    echo "     here."
    exit 1
  fi
  n1=$(run_probe $probe 1000 "")
  n2=$(run_probe $probe 9000 "")
  if [ "$n1" != "$n2" ]; then
    echo "FAIL the NATIVE build leaks on this probe ($n1 vs $n2), so the wasm"
    echo "     figure above is agreement with a leaking oracle, not a property."
    exit 1
  fi
  echo "ok  $what does not leak: $w1 bytes at 1000 and at 9000 iterations,"
  echo "..  and the native build's slope is zero too ($n1 at both) — two"
  echo "..  independent builds each leaking nothing, not two agreeing"
done

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/dyn_slice.pas" "$work" d

echo "PASS check_dyn"
