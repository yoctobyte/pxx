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

# ---- stage 3: the section layout, against ld --------------------------------
# The layout assigns every input section an output address. Its ORACLE is ld
# TOLD TO USE THE SAME OUTPUT-SECTION ADDRESSES (--section-start), which removes
# the one legitimate difference between two linkers -- where each output
# section starts -- and leaves everything this stage decides: input order,
# per-input alignment, per-name concatenation, and which definition of a name
# wins. Every global we give an address must then have THAT address in ld's
# image. One wrong weak/strong choice lands a name in a different object and
# moves it by hundreds of kilobytes, so the comparison is sharp.
#
# THE SUBJECT IS c, d, x IN THAT ORDER, and each part is there for a rule:
#   * c and x both carry crtl WEAKLY, so `exit` etc. have two weak copies and
#     only "the FIRST weak definition in link order stands" picks c's (d calls
#     nothing from crtl and so carries none -- it is the object with `main`);
#   * x defines atoi STRONGLY, after two weak copies of it, so only "a strong
#     definition displaces a weak one" picks x's -- the first-wins rule alone
#     would pick c's, and so would a table that never looks at binding;
#   * c's .text is not a multiple of 16 long, so d's .text starts on padding
#     that only per-input alignment produces.
# Each of those is asserted to be TRUE OF THE SUBJECT below, because a row
# whose subject lacks the case passes it vacuously.
command -v ld >/dev/null 2>&1 || fail "ld is not on PATH -- the layout has no oracle"
export LC_ALL=C   # sort and join must collate `_exit` and `exit` the same way;
                  # under a locale they did not, and the join invented two mismatches
cat > "$W/x.c" <<'EOF'
#include <stdlib.h>
int atoi(const char *s) { return 42; }
int viax(const char *s) { return atoi(s); }
EOF
"$COMPILER" --emit-obj "$W/x.c" "$W/x.o" > "$W/x.build.log" 2>&1 \
  || { cat "$W/x.build.log"; fail "--emit-obj did not produce x.o"; }

bindof() { readelf -sW "$W/$1.o" | awk -v n="$2" '$8==n && $7!="UND" {print $5}' | head -1; }
[ "$(bindof c atoi)" = "WEAK" ] && [ "$(bindof x atoi)" = "GLOBAL" ] \
  || fail "the subject no longer has a weak atoi in c.o and a strong one in x.o, so the strong-over-weak row would pass vacuously"
[ "$(bindof c exit)" = "WEAK" ] && [ "$(bindof x exit)" = "WEAK" ] \
  || fail "c.o and x.o no longer both carry exit weakly, so the first-weak-wins row would pass vacuously"
# `[ 1]` is TWO awk fields and `[10]` is one, so the index is stripped before
# anything counts columns: name type addr off size.
secs() { readelf -SW "$1" | sed -n 's/^ *\[ *[0-9]*\] *//p'; }
ctext=$(secs "$W/c.o" | awk '$1==".text" {print $5}')
[ $((0x$ctext % 16)) -ne 0 ] \
  || fail "c.o's .text is a multiple of 16 long, so per-input alignment is not exercised"

printf '%s\n%s\n%s\n' "$W/c.o" "$W/d.o" "$W/x.o" > "$W/cdx.lst"
PXXDBG="a.objlayout:$W/cdx.lst" "$COMPILER" > "$W/lay.out" 2>&1 || fail "the layout exited nonzero"
grep -q 'ELFLAY-OK' "$W/lay.out" || { cat "$W/lay.out"; fail "the layout did not reach its completion line"; }

starts=""
for s in text init_array fini_array data bss; do
  a=$(awk -v n=".$s" '$2=="out" && $3==n {print $4}' "$W/lay.out")
  [ -n "$a" ] || fail "the layout printed no address for .$s"
  starts="$starts --section-start=.$s=$a"
done
# shellcheck disable=SC2086
ld -static -nostdlib -e main $starts -o "$W/ref" "$W/c.o" "$W/d.o" "$W/x.o" > "$W/ld.log" 2>&1 \
  || { cat "$W/ld.log"; fail "ld could not link the subject at the layout's addresses"; }

# sizes: every output section but .bss must agree exactly. .bss is excluded by
# name because ld's default script rounds its END up to 8 and that is a script
# detail with no address consequence -- nothing is placed after it.
for s in text init_array fini_array data; do
  ours=$(awk -v n=".$s" '$2=="out" && $3==n {print $6}' "$W/lay.out")
  theirs=$(secs "$W/ref" | awk -v n=".$s" '$1==n {print $5}')
  [ "$ours" = "$((0x$theirs))" ] || fail "output .$s is $ours bytes here and $((0x$theirs)) in ld's image"
done

nm "$W/ref" | awk '$2 ~ /^[TDBWVRA]$/ {print $3, $1}' | sort > "$W/ld.syms"
awk '$2=="sym" {print $4, $3}' "$W/lay.out" | sort > "$W/our.syms"
nours=$(wc -l < "$W/our.syms" | tr -d ' ')
njoin=$(join "$W/our.syms" "$W/ld.syms" | wc -l | tr -d ' ')
nbad=$(join "$W/our.syms" "$W/ld.syms" | awk '$2!=$3' | wc -l | tr -d ' ')
[ "$nours" -gt 100 ] || fail "the layout placed only $nours globals -- the subject carries crtl, so this is a reader that found almost nothing"
[ "$njoin" = "$nours" ] || { join -v1 "$W/our.syms" "$W/ld.syms" | head >&2; fail "$((nours - njoin)) of our $nours globals are absent from ld's image"; }
[ "$nbad" = "0" ] || { join "$W/our.syms" "$W/ld.syms" | awk '$2!=$3' | head >&2; fail "$nbad of $nours globals are at a different address than ld put them"; }

# ---- positive control: an allocated section that is not ours is REFUSED -----
# The scope is pxx's own objects. `as` is binutils, like ld and readelf.
if command -v as >/dev/null 2>&1; then
  printf '\t.section .rodata\n\t.globl k\nk:\t.long 1\n' > "$W/ro.s"
  as -o "$W/ro.o" "$W/ro.s" || fail "as could not assemble the refusal control"
  printf '%s\n%s\n' "$W/c.o" "$W/ro.o" > "$W/ro.lst"
  PXXDBG="a.objlayout:$W/ro.lst" "$COMPILER" > "$W/ro.out" 2>&1
  grep -q "allocated section '.rodata' is not one pxx emits" "$W/ro.out" \
    || { cat "$W/ro.out"; fail "an object with a .rodata section was not refused by name"; }
  grep -q 'ELFLAY-OK' "$W/ro.out" && fail "the layout printed its OK line after a refusal"
else
  fail "as is not on PATH -- the refusal control has no subject"
fi

echo "elf-layout: $nours globals at the same address as ld over c/d/x, sizes agree; a foreign .rodata is refused"

# ---- stage 4: relocation application, against the same ld run ---------------
# PXXDBG=a.objlink writes <list>.exe, entered at main (the entry contract is
# stage 5). With the output addresses forced equal, every RELOCATED BYTE must
# match ld's, which is a far sharper check than behaviour: one wrong S, A or P
# anywhere in ~980 KB of code shows up as a differing byte.
#
# ONE LEGITIMATE DIFFERENCE, AND IT IS FENCED RATHER THAN IGNORED: ld fills the
# padding BETWEEN input .text sections with multi-byte NOPs (66 2e 0f 1f 84 ..)
# and we leave zeros. Nothing executes that padding. So .text is compared
# everywhere, and every differing byte must fall inside a gap the layout itself
# reports -- a difference one byte outside a gap is a relocation defect.
link() {
  PXXDBG="a.objlink:$W/$1" "$COMPILER" > "$W/$1.link" 2>&1 || fail "the linker exited nonzero on $1"
  grep -q 'ELFLINK-OK' "$W/$1.link" || { cat "$W/$1.link"; fail "the linker did not reach its completion line on $1"; }
  [ -s "$W/$1.exe" ] || fail "the linker reported OK and wrote no $1.exe"
}
link cdx.lst
for s in .init_array .fini_array .data; do
  objcopy -O binary -j "$s" "$W/cdx.lst.exe" "$W/o$s.bin" && objcopy -O binary -j "$s" "$W/ref" "$W/r$s.bin" \
    || fail "objcopy could not extract $s"
  [ -s "$W/r$s.bin" ] || fail "ld's image has an empty $s, so comparing it proves nothing"
  cmp -s "$W/o$s.bin" "$W/r$s.bin" || fail "$s differs from ld's after relocation"
done
objcopy -O binary -j .text "$W/cdx.lst.exe" "$W/o.text.bin" && objcopy -O binary -j .text "$W/ref" "$W/r.text.bin" \
  || fail "objcopy could not extract .text"
[ "$(wc -c < "$W/o.text.bin")" = "$(wc -c < "$W/r.text.bin")" ] || fail ".text is a different size from ld's"
# the gaps, as 0-based offsets into .text: [end of input n, start of input n+1)
tbase=$(awk '$2=="out" && $3==".text" {print $4}' "$W/lay.out")
awk -v b="$((tbase))" '$2=="in" && $4==".text" {print $5, $7}' "$W/lay.out" > "$W/tin"
ndiff=0; nout=0
cmp -l "$W/o.text.bin" "$W/r.text.bin" > "$W/tdiff" || true
while read -r pos _ _; do
  ndiff=$((ndiff + 1))
  off=$((pos - 1))
  ingap=0; prevend=""
  while read -r a sz; do
    s0=$((a - tbase))
    if [ -n "$prevend" ] && [ "$off" -ge "$prevend" ] && [ "$off" -lt "$s0" ]; then ingap=1; fi
    prevend=$((s0 + sz))
  done < "$W/tin"
  [ "$ingap" = 1 ] || nout=$((nout + 1))
done < "$W/tdiff"
[ "$nout" = 0 ] || fail "$nout of $ndiff differing .text bytes are OUTSIDE the inter-input padding -- a relocation was applied wrongly"
nm "$W/cdx.lst.exe" | awk '$2 ~ /^[A-Z]$/' | sort > "$W/g1"
nm "$W/ref" | awk '$2 ~ /^[A-Z]$/' | grep -vE ' (__bss_start|_edata|_end)$' | sort > "$W/g2"
cmp -s "$W/g1" "$W/g2" || { diff "$W/g1" "$W/g2" | head >&2; fail "the linked image's global symbols differ from ld's"; }
[ "$(readelf -hW "$W/cdx.lst.exe" | sed -n 's/.*Entry point address: *//p')" = "$(readelf -hW "$W/ref" | sed -n 's/.*Entry point address: *//p')" ] \
  || fail "the entry point differs from ld's"

# THE THIRD TYPE, AND ADDENDS. The c/d/x census is PC32 and 64 only: the tree
# asserts .text carries no R_X86_64_32S (test-emit-obj), so a real pxx object
# cannot supply one -- yet elfwriter still writes it for an operand its
# rip-relative rewrite does not recognise, so the applier must be right about
# it. A hand-assembled object in OUR section vocabulary exercises all three,
# each with a non-zero addend so a dropped A cannot pass.
cat > "$W/g.s" <<'EOF'
	.text
	.globl main
main:
	movq	$k+8, %rax
	leaq	k+16(%rip), %rax
	movq	$main, %rdx
	ret
	.data
	.globl k
k:	.quad	k+24
	.quad	main
	.quad	0
EOF
as -o "$W/g.o" "$W/g.s" || fail "as could not assemble the three-type subject"
for t in R_X86_64_32S R_X86_64_PC32 R_X86_64_64; do
  readelf -rW "$W/g.o" | grep -q " $t " || fail "the three-type subject carries no $t, so that row would pass vacuously"
done
printf '%s\n' "$W/g.o" > "$W/g.lst"
PXXDBG="a.objlayout:$W/g.lst" "$COMPILER" > "$W/g.lay" 2>&1
gstarts=""
for s in text data; do
  gstarts="$gstarts --section-start=.$s=$(awk -v n=".$s" '$2=="out" && $3==n {print $4}' "$W/g.lay")"
done
# shellcheck disable=SC2086
ld -static -nostdlib -e main $gstarts -o "$W/refg" "$W/g.o" > "$W/ldg.log" 2>&1 || { cat "$W/ldg.log"; fail "ld could not link the three-type subject"; }
link g.lst
for s in .text .data; do
  objcopy -O binary -j "$s" "$W/g.lst.exe" "$W/og$s.bin"; objcopy -O binary -j "$s" "$W/refg" "$W/rg$s.bin"
  cmp -s "$W/og$s.bin" "$W/rg$s.bin" || fail "the three-type subject's $s differs from ld's"
done

# ---- positive controls: what the applier must REFUSE, by name ---------------
# A 32-bit result that does not fit. ld says "relocation truncated to fit";
# keeping the low half would be a jump to a plausible wrong address.
printf '\t.text\n\t.globl main\nmain:\tmovq\t$big, %%rax\n\tret\n\t.globl big\n\t.set big, 0x100000000\n' > "$W/big.s"
as -o "$W/big.o" "$W/big.s" || fail "as could not assemble the overflow control"
ld -static -nostdlib -e main -o "$W/refbig" "$W/big.o" > "$W/ldbig.log" 2>&1 \
  && fail "ld accepted the overflow control, so it does not overflow and the row below proves nothing"
printf '%s\n' "$W/big.o" > "$W/big.lst"
PXXDBG="a.objlink:$W/big.lst" "$COMPILER" > "$W/big.out" 2>&1
grep -q 'R_X86_64_32S at .text+3 does not fit in 32 bits (value 0x0000000100000000)' "$W/big.out" \
  || { cat "$W/big.out"; fail "a 32S that does not fit was not refused by name with its true value"; }
grep -q 'ELFLINK-OK' "$W/big.out" && fail "the linker printed its OK line after refusing a relocation"
# A type pxx does not emit.
printf '\t.text\n\t.globl main\nmain:\tcall\tmain@PLT\n\tret\n' > "$W/plt.s"
as -o "$W/plt.o" "$W/plt.s" || fail "as could not assemble the PLT32 control"
printf '%s\n' "$W/plt.o" > "$W/plt.lst"
PXXDBG="a.objlink:$W/plt.lst" "$COMPILER" > "$W/plt.out" 2>&1
grep -q 'R_X86_64_PLT32 in .text -- pxx emits' "$W/plt.out" \
  || { cat "$W/plt.out"; fail "an R_X86_64_PLT32 was not refused by name"; }

echo "elf-link: relocated image matches ld byte for byte over c/d/x ($ndiff .text bytes differ, all in inter-input padding) and over a 32S/PC32/64 subject with addends; an overflowing 32S and a PLT32 are refused by name"
echo "elf-reader: agrees with readelf on sections, symbols, undefined and relocations over a defining/referencing object pair; refuses an executable and a non-ELF file by name"
echo "ELF-READER-ORACLE-COMPLETE"
