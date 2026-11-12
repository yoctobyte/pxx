#!/bin/bash
# casm_sysinsn_vs_gcc.sh PXX SRC.c TMPDIR
#
# Compile SRC.c with pxx (--emit-obj) and with gcc (-c), then compare, per
# function, the system instructions objdump reads back: the bytes and the
# text for register forms, the mnemonic alone for frame-slot forms (the two
# compilers lay frames out differently). Prints "same: N instructions" and
# exits 0, or prints both lists and exits 1.
#
# Used by test/casm_kernel_system_instructions.c, whose instructions are
# privileged and cannot be executed in user mode.
set -u
PXX=$1; SRC=$2; T=$3
mkdir -p "$T"
"$PXX" --emit-obj "$SRC" "$T/sys_pxx.o" > "$T/sys_pxx.log" 2>&1 || { cat "$T/sys_pxx.log"; exit 1; }
gcc -O1 -fno-stack-protector -c "$SRC" -o "$T/sys_gcc.o" || exit 1

pick() {
  objdump -d --no-show-raw-insn "$1" > "$T/$2.noraw"
  objdump -d "$1" | awk -v RE='^(cli|sti|hlt|swapgs|iretq|sysretq|out|in|rdmsr|wrmsr|invlpg|lgdt|lidt|ltr|mov|fxsave64|fxrstor64|fninit|ldmxcsr)$' '
    /^[0-9a-f]+ </ { fn = ($2 ~ /^<k_/) ? $2 : ""; next }
    /^ +[0-9a-f]+:\t/ {
      n = split($0, f, "\t"); if (n < 3) next
      bytes = f[2]; gsub(/ +$/, "", bytes)
      split(f[3], ins, " "); mn = ins[1]
      ops = substr(f[3], length(mn) + 1); gsub(/^ +| +$/, "", ops)
      if (fn == "" || mn !~ RE) next
      # a plain mov is only interesting when it touches a segment or control register
      if (mn ~ /^mov/ && ops !~ /%(cs|ds|es|ss|fs|gs)(,|$)|%cr[0-9]/) next
      if (ops ~ /\(%rbp\)|\(%rsp\)/) print fn, mn, "<frame>"
      else print fn, bytes, mn, ops
    }'
}
pick "$T/sys_pxx.o" pxx > "$T/sys_pxx.txt"
pick "$T/sys_gcc.o" gcc > "$T/sys_gcc.txt"
n=$(wc -l < "$T/sys_gcc.txt")
if [ "$n" -lt 30 ]; then
  echo "casm_sysinsn_vs_gcc: gcc's object shows only $n system instructions -- the picker is broken, not the encoder"
  exit 1
fi
if cmp -s "$T/sys_pxx.txt" "$T/sys_gcc.txt"; then
  echo "same: $n instructions"
  exit 0
fi
diff "$T/sys_gcc.txt" "$T/sys_pxx.txt" | sed 's/^</gcc /; s/^>/pxx /'
exit 1
