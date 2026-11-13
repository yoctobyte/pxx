#!/bin/bash
# check_gas_frontend.sh <compiler> <workprefix>
# The GNU as frontend (compiler/gasfront.inc), against GNU as itself:
#   1. test/gas_frontend.S (64-bit: cpp, macros, numeric labels, rip, PLT
#      calls into C, a .rodata table of code addresses, a symbol difference)
#      assembled by pxx and by gas, each linked by gcc with
#      test/gas_frontend_main.c: both programs print the expected text;
#   2. test/gas_frontend_code32.s: the 32-bit instruction text and every
#      relocation (type, symbol, addend) match gas's, after normalising the
#      encoding FORMS that print differently (moffs/SIB absolute, rel8/rel32);
#   3. refusals: a REX instruction and rip addressing under .code32.
set -u
PXX=$1; W=$2
fail() { echo "check_gas_frontend: FAIL: $*"; exit 1; }
command -v gcc > /dev/null || { echo "check_gas_frontend: SKIP (no gcc)"; exit 0; }

exp=$(cat test/gas_frontend.expected)
"$PXX" --emit-obj test/gas_frontend.S "$W"_p.o > "$W"_p.log 2>&1 || { cat "$W"_p.log; fail "pxx could not assemble test/gas_frontend.S"; }
gcc -c test/gas_frontend.S -o "$W"_g.o || fail "gas could not assemble test/gas_frontend.S"
for t in p g; do
  gcc -no-pie -o "$W"_$t test/gas_frontend_main.c "$W"_$t.o || fail "gcc could not link the $t object"
  got=$("$W"_$t) || fail "the $t program exited $?"
  [ "$got" = "$exp" ] || fail "the $t program printed:
$got"
done

norm() {
  objdump -dr -M i386,suffix "$1" | sed -n '/<entry32>:/,$p' |
    sed -E -e 's/^ *[0-9a-f]+:\t([0-9a-f]{2} )+ *\t/\t/' -e '/^ *[0-9a-f]+:\t([0-9a-f]{2} ?)+ *$/d' \
           -e 's/^\t\t\t[0-9a-f]+: /\t\t\t/' -e 's/\(,%eiz,1\)//' -e 's/ +[0-9a-f]+ <[^>]*>$//' \
           -e 's/^[0-9a-f]+ (<[^>]*>:)/\1/' -e 's/(R_X86_64_[A-Z0-9]+\t\.text)[+-]0x[0-9a-f]+/\1+(layout)/' \
           -e 's/[[:space:]]+$//' -e '/^$/d'
}
"$PXX" --emit-obj test/gas_frontend_code32.s "$W"_32p.o > "$W"_32p.log 2>&1 || { cat "$W"_32p.log; fail "pxx could not assemble test/gas_frontend_code32.s"; }
as test/gas_frontend_code32.s -o "$W"_32g.o || fail "gas could not assemble test/gas_frontend_code32.s"
norm "$W"_32p.o > "$W"_32p.txt
norm "$W"_32g.o > "$W"_32g.txt
[ "$(wc -l < "$W"_32g.txt)" -gt 30 ] || fail "the .code32 listing is too short to mean anything"
diff "$W"_32p.txt "$W"_32g.txt > "$W"_32.diff || { cat "$W"_32.diff; fail ".code32 instructions or relocations differ from gas"; }
# the data sections' relocations too (.multiboot, .data)
# (.rela.text is compared above, where code-local addends depend on encoding size)
rels() { readelf -rW "$1" | awk '/^Relocation section/ {s=$3} /R_X86_64/ && s != "'"'"'.rela.text'"'"'" {print s, $3, $5, $6, $7}'; }
diff <(rels "$W"_32p.o) <(rels "$W"_32g.o) || fail "relocations differ from gas"
cmp <(objcopy -O binary -j .multiboot "$W"_32p.o /dev/stdout) <(objcopy -O binary -j .multiboot "$W"_32g.o /dev/stdout) \
  || fail ".multiboot bytes differ from gas"

printf '\t.code32\n\tmovq %%rax, %%rbx\n' > "$W"_rex.s
out=$("$PXX" --emit-obj "$W"_rex.s "$W"_rex.o 2>&1) && fail "a REX instruction under .code32 was accepted"
echo "$out" | grep -q 'REX' || fail "the .code32 REX refusal does not say why: $out"
printf '\t.code32\n\tmovl x(%%rip), %%eax\n' > "$W"_rip.s
out=$("$PXX" --emit-obj "$W"_rip.s "$W"_rip.o 2>&1) && fail "rip addressing under .code32 was accepted"
echo "$out" | grep -q 'rip' || fail "the .code32 rip refusal does not say why: $out"
# 4. test/gas_frontend_code16.s: the .code16 region (up to t16b) must be
#    BYTE-IDENTICAL to gas's, with the same relocations; the .code16
#    branches (.text.br) must match as instruction text (gas relaxes them to
#    rel8, pxx keeps rel16). The .code32/.code64 tail is check 2's ground.
"$PXX" --emit-obj test/gas_frontend_code16.s "$W"_16p.o > "$W"_16p.log 2>&1 || { cat "$W"_16p.log; fail "pxx could not assemble test/gas_frontend_code16.s"; }
as test/gas_frontend_code16.s -o "$W"_16g.o || fail "gas could not assemble test/gas_frontend_code16.s"
symoff() { nm "$1" | awk -v s="$2" '$3 == s {print $1}'; }
n16=$(symoff "$W"_16g.o t16b)
[ -n "$n16" ] && [ "$n16" = "$(symoff "$W"_16p.o t16b)" ] || fail ".code16: t16b is at $(symoff "$W"_16p.o t16b) in pxx's object, $n16 in gas's"
n16=$((16#$n16))
[ "$n16" -gt 150 ] || fail "the .code16 region is too short to mean anything"
for t in p g; do objcopy -O binary -j .text "$W"_16$t.o "$W"_16$t.bin; head -c "$n16" "$W"_16$t.bin > "$W"_16$t.r16; done
cmp "$W"_16p.r16 "$W"_16g.r16 || {
  objdump -d -M i8086,suffix -j .text "$W"_16p.o | head -120 > "$W"_16p.lst
  objdump -d -M i8086,suffix -j .text "$W"_16g.o | head -120 > "$W"_16g.lst
  diff "$W"_16p.lst "$W"_16g.lst; fail ".code16 bytes differ from gas"; }
# offsets are 16 hex digits, so a string compare is a numeric one (mawk has no strtonum)
rel16() { readelf -rW "$1" | awk -v n="$(printf '%016x' "$n16")" '/R_X86_64/ && $1 < n {print $1, $3, $5, $6, $7}'; }
diff <(rel16 "$W"_16p.o) <(rel16 "$W"_16g.o) || fail ".code16 relocations differ from gas"
[ "$(rel16 "$W"_16g.o | wc -l)" -ge 2 ] || fail "the .code16 region has too few relocations to mean anything"
br16() { objdump -d -M i8086,suffix -j .text.br "$1" | sed -n '/^ *[0-9a-f]*:/p' | cut -f3 |
         sed -E -e 's/ +[0-9a-f]+ <.*>$//' -e 's/[[:space:]]+$//' -e 's/^jmpw$/jmp/'; }
diff <(br16 "$W"_16p.o) <(br16 "$W"_16g.o) || fail ".code16 branches differ from gas"
printf '\t.code16\n\tmovw (%%bx), %%ax\n' > "$W"_bx.s
out=$("$PXX" --emit-obj "$W"_bx.s "$W"_bx.o 2>&1) && fail "16-bit addressing under .code16 was accepted"
echo "$out" | grep -q '16-bit addressing' || fail "the .code16 (%bx) refusal does not say why: $out"
echo "check_gas_frontend: OK"
