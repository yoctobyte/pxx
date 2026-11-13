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
echo "check_gas_frontend: OK"
