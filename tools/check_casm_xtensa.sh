#!/bin/sh
# Disassemble pxx's encoding of test/c_xtensa_inline_asm_sys.c with Espressif's
# objdump and compare the instructions each asm template produced against what
# GNU as would have been asked to assemble. The oracle is the vendor
# disassembler, so a wrong byte shows up as a wrong mnemonic or register.
# Exits 0 (and says so) when the toolchain is absent.
# usage: tools/check_casm_xtensa.sh <compiler> <tmpdir>
set -e
cc=$1; tmp=$2
od=$(ls "$HOME"/.espressif/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin/xtensa-esp32s3-elf-objdump 2>/dev/null | tail -n 1)
if [ -z "$od" ]; then echo "check_casm_xtensa: no xtensa-esp32s3-elf-objdump, NOT verified"; exit 0; fi
"$cc" --target=esp32s3 --freestanding --emit-obj test/c_xtensa_inline_asm_sys.c "$tmp/c_xtasm_sys.o" > /dev/null
"$od" -d "$tmp/c_xtasm_sys.o" > "$tmp/c_xtasm_sys.dis"
got=$(grep -E '	(rsr|wsr|xsr|rur|wur|rsil|waiti|memw|isync|esync|dsync|rsync)([. 	]|$)' "$tmp/c_xtasm_sys.dis" | sed 's/^[^	]*	[^	]*	//' | tr '\t' ' ')
want='rsr.ps a3
wsr.intenable a3
rsync
rsr.ccount a3
wsr.ccompare0 a3
xsr.vecbase a3
rsil a3, 15
wsr.ps a3
rsync
waiti 0
rur.threadptr a3
wur.threadptr a3
memw
isync
esync
dsync
rsr.excsave1 a3'
# An instruction pxx cannot encode, in a static inline nobody calls, must not
# stop the compile (gcc never emits that routine; rump-pxx g20) -- and a call
# to it must refuse by name.
printf 'static inline void f(void){__asm__ volatile("frobnicate a2, a3");}\nint g(void){return 1;}\n' > "$tmp/c_xtasm_unused.c"
"$cc" --target=esp32s3 --freestanding --emit-obj "$tmp/c_xtasm_unused.c" "$tmp/c_xtasm_unused.o" > /dev/null || { echo "check_casm_xtensa: FAIL (unused static inline stopped the compile)"; exit 1; }
printf 'static inline void f(void){__asm__ volatile("frobnicate a2, a3");}\nint g(void){f(); return 1;}\n' > "$tmp/c_xtasm_called.c"
if "$cc" --target=esp32s3 --freestanding --emit-obj "$tmp/c_xtasm_called.c" "$tmp/c_xtasm_called.o" > "$tmp/c_xtasm_called.log" 2>&1; then echo "check_casm_xtensa: FAIL (a call to the poisoned routine compiled)"; exit 1; fi
grep -q 'cannot call f: its inline asm uses "frobnicate' "$tmp/c_xtasm_called.log" || { echo "check_casm_xtensa: FAIL (wrong refusal)"; cat "$tmp/c_xtasm_called.log"; exit 1; }
if [ "$got" = "$want" ]; then echo "check_casm_xtensa: OK"; exit 0; fi
echo "check_casm_xtensa: FAIL"; echo "--- want"; echo "$want"; echo "--- got"; echo "$got"; exit 1
