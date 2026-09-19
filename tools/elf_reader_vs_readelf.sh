#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
#
# THE ELF OBJECT READER, CHECKED AGAINST readelf.
#
# compiler/elfreader.inc is the first code in this compiler that READS an
# object rather than writing one, and it is the stage every later stage of
# feature-a-pxx-cannot-link-its-own-objects rests on: a symbol-table merge, a
# section layout and a relocation applier all consume what it reports. If it
# enumerates wrongly, every later stage is unfalsifiable -- it produces a
# plausible wrong answer that no downstream assertion can attribute. So it is
# checked on its own, now, against an instrument that FAILS DIFFERENTLY from
# anything in this repo. Two readings that can go wrong the same way are one
# reading; readelf is binutils' parser of the same bytes and shares no code,
# no author and no assumption with ours.
#
# THE ORACLE NEEDS THE SAME CARE AS THE INSTRUMENT, and this script exists in
# the shape it does because the first hand-run of it produced TWO false
# disagreements, both in the oracle:
#   * `readelf -SW | grep -c '^  \['` counts the `[Nr]` COLUMN HEADER as a
#     section, so it answered 12 for an 11-section object. e_shnum is read from
#     the header here instead, which is the number itself rather than a count
#     of lines that look like it.
#   * the only UND symbol in an object with no unresolved references is index
#     0, the RESERVED NULL SYMBOL, which every symbol table has. Counting it
#     reports one undefined symbol in a file that has none. Index 0 is excluded
#     on both sides, by name.
# Both would have sent someone to "fix" a correct reader. A disagreement with
# an oracle is a question about BOTH readings.
#
# THE UNDEFINED COUNT IS THE ROW THAT CANNOT BE ALLOWED TO COLLIDE. A
# self-contained object has ZERO undefined symbols -- and zero is also what a
# reader that never finds any would print, so that row alone certifies a broken
# reader. The subject is therefore a PAIR: a.o defines helper() and must report
# 0, b.o calls it and must report exactly 1, named `helper` by the oracle. The
# asymmetry is the control.
#
# COVERS TWO STAGES: the object READER (against readelf) and the symbol-table
# MERGE over a set of objects (three cases no two of which can pass for each
# other, plus the weak-does-not-collide property that lets 400 busybox objects
# link at all).
#
# Prints ELF-READER-ORACLE-COMPLETE on success. Exits nonzero on any mismatch.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
COMPILER="${PXX_COMPILER:-./compiler/pascal26}"
W="$(mktemp -d "${TMPDIR:-/tmp}/elfrd-oracle-XXXXXX")"
trap 'rm -rf "$W"' EXIT

fail() { echo "FAIL elf-reader: $*" >&2; exit 1; }

command -v readelf >/dev/null 2>&1 || fail "readelf is not on PATH -- this guard has no oracle and a skip here would be coverage that is not there"
[ -x "$COMPILER" ] || fail "no compiler at $COMPILER"

cat > "$W/a.c" <<'EOF'
int helper(int x);
int helper(int x){ return x + 1; }
EOF
cat > "$W/b.c" <<'EOF'
int helper(int x);
int main(void){ return helper(41); }
EOF

for o in a b; do
  "$COMPILER" --emit-obj "$W/$o.c" "$W/$o.o" > "$W/$o.build.log" 2>&1 \
    || { cat "$W/$o.build.log"; fail "--emit-obj did not produce $o.o"; }
  # ASSERT THE PRECONDITION AND BRANCH ON IT: a comparison whose inputs were
  # never proven to exist cannot fail.
  [ -s "$W/$o.o" ] || fail "$o.o is empty or absent"
done

# ---- our reader -------------------------------------------------------------
for o in a b; do
  PXXDBG="a.obj:$W/$o.o" "$COMPILER" > "$W/$o.rd" 2>&1 \
    || fail "the reader exited nonzero on $o.o"
  grep -q 'ELFRD-OK' "$W/$o.rd" \
    || { cat "$W/$o.rd"; fail "the reader did not reach its own completion line on $o.o"; }
done

ours_sections()  { sed -n 's/^elfrd: sections \([0-9]*\)$/\1/p' "$W/$1.rd"; }
ours_symbols()   { sed -n 's/^elfrd: symbols \([0-9]*\) .*/\1/p' "$W/$1.rd"; }
ours_undefined() { sed -n 's/^elfrd: symbols [0-9]* defined [0-9]* undefined \([0-9]*\)$/\1/p' "$W/$1.rd"; }
ours_relocs()    { sed -n 's/^elfrd: relocations \([0-9]*\)$/\1/p' "$W/$1.rd"; }

# ---- the oracle -------------------------------------------------------------
# e_shnum from the HEADER, not a count of listing lines (see the note above).
they_sections()  { readelf -hW "$W/$1.o" | sed -n 's/.*Number of section headers: *\([0-9]*\).*/\1/p'; }
they_symbols()   { readelf -sW "$W/$1.o" | grep -cE '^ *[0-9]+:'; }
# INDEX 0 EXCLUDED ON BOTH SIDES: the reserved null symbol is UND in every
# object and is not a symbol any linker resolves.
they_undefined() { readelf -sW "$W/$1.o" | grep -E '^ *[0-9]+:' | awk '$1!="0:" && $7=="UND"' | wc -l | tr -d ' '; }
they_relocs()    { readelf -rW "$W/$1.o" | grep -cE '^[0-9a-f]{16}'; }

for o in a b; do
  for field in sections symbols undefined relocs; do
    mine=$(ours_$field "$o")
    theirs=$(they_$field "$o")
    [ -n "$mine" ] || fail "our reader printed no $field for $o.o"
    [ -n "$theirs" ] || fail "readelf printed no $field for $o.o"
    if [ "$mine" != "$theirs" ]; then
      echo "  $o.o $field: ours=$mine readelf=$theirs" >&2
      fail "$o.o $field disagrees with the oracle"
    fi
  done
done

# ---- the asymmetry that stops zero certifying a broken reader ---------------
[ "$(ours_undefined a)" = "0" ] || fail "a.o defines helper and should have no undefined symbols"
[ "$(ours_undefined b)" = "1" ] || fail "b.o calls helper and must report exactly one undefined symbol -- a reader that always answers 0 passes a.o"
readelf -sW "$W/b.o" | grep -E '^ *[0-9]+:' | awk '$1!="0:" && $7=="UND"' | grep -q 'helper' \
  || fail "the oracle does not agree that b.o's undefined symbol is helper -- the subject changed under this row"

# ---- the relocation histogram must account for every relocation ------------
grep -q 'does not account for all' "$W/a.rd" "$W/b.rd" \
  && fail "the reader reported a relocation type outside the histogram's range"

# ---- positive control: it must REFUSE what it cannot read -------------------
# An EXECUTABLE is not a relocatable object. A reader that decodes one anyway
# would produce plausible nonsense, so the refusal is asserted by NAME rather
# than by exit status.
"$COMPILER" "$W/b.c" "$W/b.exe" > "$W/exe.log" 2>&1 || fail "could not build an executable for the negative control"
PXXDBG="a.obj:$W/b.exe" "$COMPILER" > "$W/exe.rd" 2>&1
grep -q 'e_type is not ET_REL' "$W/exe.rd" \
  || { cat "$W/exe.rd"; fail "the reader accepted an EXECUTABLE as a relocatable object -- the refusal that makes this reader trustworthy did not fire"; }
grep -q 'ELFRD-OK' "$W/exe.rd" \
  && fail "the reader printed its OK line for an input it had just refused"

# A file that is not ELF at all must be refused too, and differently. IT MUST BE
# LONG ENOUGH TO REACH THE MAGIC CHECK: the first version of this row wrote 23
# bytes and was refused for being "shorter than an ELF64 header", which is a
# correct refusal by the WRONG route -- the magic check never ran and the row
# asserted a message that had not fired. Padding to 128 bytes makes the probe
# reach the door it is about. Both refusals are real; only one is this row's.
{ printf 'not an elf file at all\n'; dd if=/dev/zero bs=1 count=104 2>/dev/null | tr '\0' 'x'; } > "$W/junk.o"
[ "$(wc -c < "$W/junk.o")" -ge 64 ] || fail "the non-ELF control is shorter than an ELF header, so it tests the length check and not the magic check"
PXXDBG="a.obj:$W/junk.o" "$COMPILER" > "$W/junk.rd" 2>&1
grep -q 'no ELF magic' "$W/junk.rd" \
  || { cat "$W/junk.rd"; fail "a non-ELF file was not refused by name"; }

# ---- stage 2: the symbol-table merge ---------------------------------------
# The reader answers "what is in this object". The merge answers "what does
# this SET still need, and what does it define twice" -- the two questions a
# linker settles before it lays anything out. Three cases, and the point is
# that no two of them can pass for each other:
#   pair      a.o defines helper, b.o calls it   -> 0 unresolved, 0 duplicate
#   lone      b.o alone                          -> exactly 1 unresolved, named
#   doubled   a.o listed twice                   -> exactly 1 duplicate, named
# The doubled case is the one that cannot be faked by a merge that does
# nothing: a table that never records a definition reports 0 duplicates, and a
# table that never records a reference reports 0 unresolved, so the two zeros
# in the PAIR row are only meaningful beside the two non-zeros below them.
printf '%s\n%s\n' "$W/a.o" "$W/b.o" > "$W/both.lst"
printf '%s\n'       "$W/b.o"         > "$W/one.lst"
printf '%s\n%s\n' "$W/a.o" "$W/a.o" > "$W/dbl.lst"

merge() {
  PXXDBG="a.objmerge:$W/$1" "$COMPILER" > "$W/$1.out" 2>&1 \
    || fail "the merge exited nonzero on $1"
  grep -q 'ELFLNK-OK' "$W/$1.out" || { cat "$W/$1.out"; fail "the merge did not reach its completion line on $1"; }
}
mfield() { sed -n "s/^elflnk: $2 \([0-9]*\)\$/\1/p" "$W/$1.out"; }

merge both.lst; merge one.lst; merge dbl.lst

[ "$(mfield both.lst unresolved)" = "0" ] || fail "a.o+b.o: helper is defined by a.o and must resolve"
[ "$(mfield both.lst duplicate)"  = "0" ] || fail "a.o+b.o: nothing is defined twice"
[ "$(mfield one.lst  unresolved)" = "1" ] || fail "b.o alone must have exactly one unresolved symbol"
grep -q '^elflnk: undef helper$' "$W/one.lst.out" \
  || fail "b.o's unresolved symbol must be NAMED helper -- a count alone is not actionable, and the one time this mattered here the answer was a single symbol behind a glibc stub"
[ "$(mfield dbl.lst duplicate)" = "1" ] || fail "a.o listed twice must report exactly one duplicate definition"
grep -q '^elflnk: dup helper x2$' "$W/dbl.lst.out" \
  || fail "the duplicate must be named helper, seen twice"

# WEAK DEFINITIONS MUST NOT COLLIDE, which is the property that lets 400
# busybox objects link at all: every C object carries the whole crtl runtime,
# exported WEAK. A merge that treated weak like strong would report hundreds of
# duplicates on any two real objects and refuse a correct program.
#
# c.c USES crtl ON PURPOSE. An object that calls nothing from it has no weak
# exports at all -- measured: a trivial two-line C file gives 1 GLOBAL and 492
# LOCAL and not one WEAK -- so a subject that does not touch printf/strlen
# cannot exercise this row and would pass it vacuously.
cat > "$W/c.c" <<'EOF'
#include <stdio.h>
#include <string.h>
int use(const char*s){ printf("%s", s); return strlen(s); }
EOF
cat > "$W/d.c" <<'EOF'
int use(const char*s);
int main(void){ return use("hi"); }
EOF
for o in c d; do
  "$COMPILER" --emit-obj "$W/$o.c" "$W/$o.o" > "$W/$o.build.log" 2>&1 \
    || { cat "$W/$o.build.log"; fail "--emit-obj did not produce $o.o"; }
done
printf '%s\n%s\n' "$W/c.o" "$W/d.o" > "$W/cd.lst"
merge cd.lst
[ "$(mfield cd.lst duplicate)" = "0" ] \
  || fail "two objects both carrying crtl weakly must not collide -- weak definitions do not duplicate"
[ "$(mfield cd.lst unresolved)" = "0" ] \
  || fail "c.o defines use and d.o calls it; nothing should be left unresolved"
# ASSERT THE ROW ACTUALLY EXERCISED WEAK, rather than passing because there
# were none: the oracle must agree that these objects carry weak definitions.
oracle_weak=$(readelf -sW "$W/c.o" | grep -E '^ *[0-9]+:' | awk '$5=="WEAK" && $7!="UND" {print $8}' | sort -u | wc -l | tr -d ' ')
[ "$oracle_weak" -gt 0 ] \
  || fail "c.o carries no WEAK definitions, so the no-collision row above proved nothing"
[ "$(mfield cd.lst weakonly)" -gt 0 ] \
  || fail "the merge reports no weak-only symbols for a pair that readelf says has $oracle_weak"

echo "elf-reader: agrees with readelf on sections, symbols, undefined and relocations over a defining/referencing object pair; refuses an executable and a non-ELF file by name"
echo "ELF-READER-ORACLE-COMPLETE"
