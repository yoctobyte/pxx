#!/bin/sh
# Byte-identity control for the argument/slot split (step 1 of
# bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee).
#
# The claim under control is "this refactor is INERT": every argument still maps
# to exactly one slot, so not one emitted byte may move. A passing test suite
# does not establish that -- it establishes that nothing OBSERVED moved. Byte
# identity of the emitted images does.
#
# WHAT THIS SCRIPT IS BUILT AGAINST is not a wrong comparison, it is a
# comparison with nothing in it. Measured while writing it: the first version
# emitted OBJECTS, and --emit-obj has no writer for aarch64 or arm32, so it
# recorded 11 rows that were all x86-64 and i386 and would have reported "all
# rows byte-identical" while proving nothing whatever about two of its four
# targets. The total was non-empty and still the population was.
# Hence, and each one BRANCHED ON rather than merely printed:
#   * every named source must exist (a glob that matches nothing is the bug);
#   * every REQUIRED TARGET must contribute at least one row -- the check the
#     first version lacked, and the one that catches this class;
#   * built vs attempted is reported, and zero built is a refusal;
#   * the row COUNT must match the baseline, so a row that stops building
#     cannot pass by dropping out of the comparison;
#   * a MUST-DIFFER row is required to actually differ, proving the hashing and
#     comparison path can report RED at all.
#
# usage: argslot_inertness.sh record  <outdir>   # before the change
#        argslot_inertness.sh compare <outdir>   # after the change
set -u
MODE="${1:?record|compare}"
OUT="${2:?output dir}"
CC=./compiler/pascal26
TMP="$OUT/img"
REQUIRED_TARGETS="x86_64 i386 aarch64 arm32"
mkdir -p "$TMP" || exit 2
[ -x "$CC" ] || { echo "argslot-inertness: no compiler at $CC"; exit 2; }

# Named one by one, never globbed: sources chosen for CALL SHAPES.
SRCS="test/c_abi_mixed_link_pxx.c
test/cabi_intra.c
test/cexternal_proc_addr_callable.c
test/c_abi_glibc_oracle.c
test/c_abi_pure_c_control.c
test/c_abi_indirect_stackargs.c"

attempted=0; built=0
: > "$OUT/hashes.new"
for s in $SRCS; do
  [ -f "$s" ] || { echo "argslot-inertness: MISSING SOURCE $s -- the corpus is not what it says"; exit 2; }
  for t in $REQUIRED_TARGETS; do
    attempted=$((attempted+1))
    o="$TMP/$(basename "$s" .c).$t"
    rm -f "$o"
    if $CC --target=$t --system-libs=c "$s" "$o" >/dev/null 2>&1 && [ -s "$o" ]; then
      built=$((built+1))
      echo "$(sha256sum "$o" | cut -d' ' -f1)  $(basename "$o")" >> "$OUT/hashes.new"
    fi
  done
done

echo "argslot-inertness: $built of $attempted (source,target) pairs produced an image"
[ "$built" -gt 0 ] || { echo "argslot-inertness: REFUSING -- nothing was built, so a comparison would be about nothing"; exit 2; }

# The check the object-based first version did not have. A target with zero rows
# is a target this harness says nothing about, and saying nothing quietly is how
# it would have passed.
for t in $REQUIRED_TARGETS; do
  n=$(grep -c "\.$t\$" "$OUT/hashes.new" || true)
  echo "argslot-inertness:   $t: $n row(s)"
  [ "$n" -gt 0 ] || { echo "argslot-inertness: REFUSING -- target $t contributed NO rows, so this run cannot speak for it"; exit 2; }
done

sort -o "$OUT/hashes.new" "$OUT/hashes.new"

# POSITIVE CONTROL: a row that MUST differ. Same source, -O0 against the default,
# so the comparison path is proven able to report RED on this very run. Without
# it a harness whose hashing silently returned a constant would print GREEN.
ctlA="$TMP/positive_control.O0"; ctlB="$TMP/positive_control.default"
# c_abi_pure_c_control.c, not cabi_intra.c: the latter has no main -- it is a
# unit a Pascal program uses -- so it cannot link as a program and the control
# refused to build. Caught by the "did the control BUILD" branch above, which is
# the reason that branch exists rather than trusting the compile to have worked.
$CC -O0 --system-libs=c test/c_abi_pure_c_control.c "$ctlA" >/dev/null 2>&1
$CC     --system-libs=c test/c_abi_pure_c_control.c "$ctlB" >/dev/null 2>&1
if [ ! -s "$ctlA" ] || [ ! -s "$ctlB" ]; then
  echo "argslot-inertness: REFUSING -- the positive control did not BUILD, so it proves nothing"; exit 2
fi
if [ "$(sha256sum "$ctlA" | cut -d' ' -f1)" = "$(sha256sum "$ctlB" | cut -d' ' -f1)" ]; then
  echo "argslot-inertness: REFUSING -- the must-differ control did NOT differ; this harness cannot report RED"; exit 2
fi
echo "argslot-inertness: positive control fired (-O0 differs from default)"

if [ "$MODE" = record ]; then
  cp "$OUT/hashes.new" "$OUT/hashes.base" || exit 2
  echo "argslot-inertness: baseline recorded ($built rows)"
  exit 0
fi

[ -s "$OUT/hashes.base" ] || { echo "argslot-inertness: no baseline to compare against"; exit 2; }
base_rows=$(wc -l < "$OUT/hashes.base"); new_rows=$(wc -l < "$OUT/hashes.new")
if [ "$base_rows" != "$new_rows" ]; then
  echo "argslot-inertness: RED -- baseline has $base_rows rows, this run $new_rows."
  echo "  A row that stopped BUILDING is not an inert change, and dropping it from"
  echo "  the comparison would have made this pass."
  exit 1
fi
if cmp -s "$OUT/hashes.base" "$OUT/hashes.new"; then
  echo "argslot-inertness: GREEN -- all $new_rows images byte-identical across $REQUIRED_TARGETS"
  exit 0
fi
echo "argslot-inertness: RED -- emitted bytes moved:"
diff "$OUT/hashes.base" "$OUT/hashes.new" | sed 's/^/    /'
exit 1

# CAN-CONTAIN PROOFS (frankA's check, and it is NOT the same as "the corpus is
# non-empty and every file built"). A corpus can be full of files and empty of
# the CONSTRUCT: their @proc census had a real corpus, every file built, every
# comparison ran, and the test source took no procedure address.
# Executed 2026-09-01 against this corpus, by injecting a `nop` into each arm,
# rebuilding, and requiring RED:
#   direct SysV cdecl arm    -> 3 rows moved (c_abi_glibc_oracle, c_abi_pure_c_control,
#                               c_abi_indirect_stackargs, all x86_64)
#   indirect cdecl arm       -> 1 row moved (c_abi_indirect_stackargs.x86_64)
#   x86-64 CALLEE spill      -> 2 rows moved (c_abi_indirect_stackargs.x86_64,
#                               c_abi_pure_c_control.x86_64)
# Two of the four x86_64 rows reach the callee arm, not all four -- recorded as
# the number it is rather than rounded up to "the corpus covers it".
# The indirect arm rests on a SINGLE source. That is real coverage and it is
# thin; a second indirect-call source would be the cheapest strengthening here.
# Neither proof is re-run automatically -- they are claims about the corpus, and
# they go stale if the sources change. Re-run them if you edit SRCS.
