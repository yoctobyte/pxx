#!/bin/sh
# Compare the ALLOCATABLE content of two linked ELF binaries, section by
# section, and report the symbol-table delta separately.
#
# WHY THIS EXISTS. --function-sections used to be verified by `cmp` over whole
# linked binaries: with one .text it had no observable effect, so proving it
# changed nothing was the only available check. That stopped being true when the
# init/fini thunks got LOCAL symbols of their own -- the flag now adds two
# entries to .symtab, so the FILES differ by 88 bytes while every byte the
# program can execute or read is the same. Whole-file `cmp` would report that as
# a failure, and the honest replacement is not to drop the check but to say
# precisely which part must not move.
#
# ANTI-VACUITY IS THE POINT. The first version of this comparison was a loop
# that extracted sections with objcopy and compared them, and it printed
# "identical" having compared ZERO sections, because the extraction silently
# produced nothing. A comparison whose inputs were never proven to exist cannot
# fail. So this script COUNTS what it actually compared and fails if that count
# is below a floor, and the floor is an argument rather than a constant so the
# caller states what its fixture must contain.
#
# usage: tools/elf_alloc_same.sh <a> <b> [min-sections]
set -u
A="$1"; B="$2"; MIN="${3:-3}"
[ -s "$A" ] || { echo "elf-alloc-same: $A missing or empty"; exit 1; }
[ -s "$B" ] || { echo "elf-alloc-same: $B missing or empty"; exit 1; }
command -v objcopy >/dev/null 2>&1 || { echo "elf-alloc-same: objcopy not installed"; exit 1; }

TMP="${TMPDIR:-/tmp}/elfalloc.$$"
mkdir -p "$TMP" || exit 1
trap 'rm -rf "$TMP"' EXIT

n=0; bad=0
for s in .text .data .rodata .init_array .fini_array; do
  objcopy -O binary --only-section="$s" "$A" "$TMP/a$s" 2>/dev/null
  objcopy -O binary --only-section="$s" "$B" "$TMP/b$s" 2>/dev/null
  # A section absent from BOTH is not a failure; absent from one is.
  ea=0; eb=0
  [ -s "$TMP/a$s" ] && ea=1
  [ -s "$TMP/b$s" ] && eb=1
  if [ "$ea" != "$eb" ]; then
    echo "elf-alloc-same: $s present in only one of the two binaries"
    bad=$((bad+1)); continue
  fi
  [ "$ea" = 1 ] || continue
  n=$((n+1))
  if ! cmp -s "$TMP/a$s" "$TMP/b$s"; then
    echo "elf-alloc-same: $s DIFFERS ($(stat -c%s "$TMP/a$s") vs $(stat -c%s "$TMP/b$s") bytes)"
    bad=$((bad+1))
  fi
done

if [ "$n" -lt "$MIN" ]; then
  echo "elf-alloc-same: only $n allocatable section(s) compared, below the floor of $MIN -- this check would have passed vacuously"
  exit 1
fi
[ "$bad" = 0 ] || exit 1

# The symbol delta, reported rather than asserted: the caller decides which new
# symbols are legitimate, because that is a property of the change under test
# and not of ELF.
readelf -sW "$A" | awk 'NF>7{print $8}' | LC_ALL=C sort -u > "$TMP/syma"
readelf -sW "$B" | awk 'NF>7{print $8}' | LC_ALL=C sort -u > "$TMP/symb"
# LC_ALL=C on BOTH the sort and the comm, and this is not a tidiness point: the
# first version left the locale alone, so `sort -u' collated one way and `comm'
# expected another. comm printed "file 1 is not in sorted order" to stderr and
# then produced a 60-name added list and a 59-name removed list of the SAME
# symbols -- and still exited 0. The verdict said identical while the body said
# the symbol tables had been rewritten. A warning that does not change the exit
# code is a refutation you have to read.
added=$(LC_ALL=C comm -13 "$TMP/syma" "$TMP/symb" | tr '\n' ' ')
removed=$(LC_ALL=C comm -23 "$TMP/syma" "$TMP/symb" | tr '\n' ' ')
echo "elf-alloc-same: $n allocatable section(s) identical; symbols added: [${added:-none}] removed: [${removed:-none}]"
exit 0
