#!/usr/bin/env bash
# pascal26 --link --freestanding: a kernel image (Gibux item 4, 2026-11-12).
#
#   tools/check_link_freestanding.sh <pascal26> <workdir>
#
# Links test/c_link_freestanding_kernel_boot.s (assembled by `as`, the way the
# kernel's .S files are until pxx has a .S frontend) with
# test/c_link_freestanding_kernel_main.c (pxx, --emit-obj --freestanding) at
# the kernel-half base 0xFFFFFFFF80100000 with entry start32, then checks the
# image by VALUE, not by layout:
#   - the entry is start32; .multiboot is the first section, at file offset
#     0x1000 (a boot loader searches the first 8 KiB);
#   - the header's R_X86_64_32 words are mb_header, __executable_start, _edata,
#     _end and start32 minus KERNEL_VMA, with the linker-defined symbols where
#     ld puts them (_edata = end of .data, _end past the largest .bss);
#   - .rodata's R_X86_64_64 words are kmain and ktable;
#   - kbanner (C static data) points at the string "kernel" in the image;
#   - .note.Xen (PVH entry) is kept, covered by a PT_NOTE inside the RX
#     PT_LOAD; --load-offset=KERNEL_VMA sets p_paddr = p_vaddr - KERNEL_VMA.
# Controls: the same link without --freestanding refuses .multiboot by name;
# without -e it refuses for want of an entry; and a compile (not a link) with
# a kernel-half --image-base is refused.
# The end-to-end proof is Gibux itself booting under qemu (done by hand
# 2026-11-12: "Hello from user space", isa-debug-exit 33); this is the part a
# gate can run.
set -u
PXX=$1; W=$2
fail() { echo "link-freestanding: FAIL: $*"; exit 1; }
mkdir -p "$W" || exit 1
VMA=0xFFFFFFFF80000000
BASE=0xFFFFFFFF80100000

as -o "$W/kboot.o" test/c_link_freestanding_kernel_boot.s || fail "as could not assemble the boot half"
"$PXX" --emit-obj --freestanding test/c_link_freestanding_kernel_main.c "$W/kmain.o" > "$W/cc.log" 2>&1 \
  || { cat "$W/cc.log"; fail "pxx could not compile the C half"; }
"$PXX" --link --freestanding --image-base=$BASE -e start32 -o "$W/k.elf" "$W/kboot.o" "$W/kmain.o" \
  > "$W/link.log" 2>&1 || { cat "$W/link.log"; fail "the freestanding link failed"; }

sym() { nm "$W/k.elf" | awk -v n="$1" '$3==n {print $1}'; }
u32() { od -An -t u4 -j "$1" -N 4 "$W/k.elf" | tr -d ' '; }
x64() { od -An -t x8 -j "$1" -N 8 "$W/k.elf" | tr -d ' '; }
for s in start32 mb_header __executable_start _edata _end kmain ktable big_bss kbanner; do
  [ -n "$(sym $s)" ] || fail "no symbol $s in the image"
done

entry=$(readelf -hW "$W/k.elf" | awk '/Entry point/ {print $4}')
[ "$((entry))" = "$((0x$(sym start32)))" ] || fail "entry $entry is not start32 (0x$(sym start32))"
first=$(readelf -SW "$W/k.elf" | awk '$1=="[" && $2=="1]" {print $3, $6}')
[ "$first" = ".multiboot 001000" ] || fail "section 1 is '$first', not .multiboot at file offset 0x1000"

[ "$(u32 4096)" = "$((0x1BADB002))" ] || fail "no multiboot magic at file offset 0x1000"
i=1
for s in mb_header __executable_start _edata _end start32; do
  want=$(( 0x$(sym $s) - VMA ))
  got=$(u32 $((4096 + 4 * i)))
  [ "$got" = "$want" ] || fail "header word $i ($s - KERNEL_VMA) is $got, want $want"
  i=$((i + 1))
done
[ "$(( 0x$(sym __executable_start) ))" = "$((BASE))" ] || fail "__executable_start is not the image base"

data=$(readelf -SW "$W/k.elf" | awk '{ for (i = 1; i <= NF; i++) if ($i == ".data") print $(i + 2), $(i + 4) }')
[ "$(( 0x${data% *} + 0x${data#* } ))" = "$(( 0x$(sym _edata) ))" ] || fail "_edata is not the end of .data ($data)"
# a difference, because both are negative as bash's signed 64-bit integers
[ $(( 0x$(sym _end) - 0x$(sym big_bss) )) -ge 4096 ] || fail "_end is not past the end of big_bss"

ro=$(( 0x$(sym ktable) - BASE ))
[ "$(x64 $ro)" = "$(sym kmain)" ] || fail "ktable[0] is $(x64 $ro), not kmain $(sym kmain)"
[ "$(x64 $((ro + 8)))" = "$(sym ktable)" ] || fail "ktable[1] is not ktable"

kb=$(x64 $(( 0x$(sym kbanner) - BASE )))
str=$(dd if="$W/k.elf" bs=1 skip=$(( 0x$kb - BASE )) count=6 2>/dev/null)
[ "$str" = "kernel" ] || fail "kbanner points at '$str', not \"kernel\""

# No SSE or x87 instruction anywhere in the image (gcc's -mgeneral-regs-only):
# a kernel runs with the user's FPU state live in those registers. ksum's
# variadic prologue is what used to spill xmm0..xmm7.
SSE='%xmm|%ymm|%zmm|%st\b|%st\(|\bf(ld|st|stp|add|mul|sub|div|ild|ist|istp|xch|chs|abs|sqrt|nstcw|ldcw|wait|nsave|rstor)\b|cvt|\bmovs[sd]\b|movap|movup|movdq|\bmovq\b.*%xmm|pxor|xorp[sd]|ldmxcsr|stmxcsr'
nsse=$(objdump -d --no-show-raw-insn "$W/k.elf" | grep -cE "$SSE")
[ "$nsse" = 0 ] || { objdump -d --no-show-raw-insn "$W/k.elf" | grep -E "$SSE|>:$" | grep -B1 -E "$SSE" | head -20; \
  fail "$nsse SSE/x87 instruction(s) in a --freestanding image"; }

# No access below rsp (gcc's -mno-red-zone): an interrupt arrives on the same
# stack and overwrites it.
nrz=$(objdump -d --no-show-raw-insn "$W/k.elf" | grep -cE -- '-0x[0-9a-f]+\(%rsp')
[ "$nrz" = 0 ] || { objdump -d --no-show-raw-insn "$W/k.elf" | grep -E -- '-0x[0-9a-f]+\(%rsp' | head; \
  fail "$nrz access(es) below rsp in a --freestanding image"; }

# The PVH entry note (.note.Xen): kept with nothing referencing it, inside the
# RX PT_LOAD, covered by a PT_NOTE, its descriptor relocated to start32's
# physical address. Without --load-offset every p_paddr equals p_vaddr.
seg() { readelf -lW "$1" | awk -v t="$2" '$1==t {print $2, $3, $4, $5}'; }
note=$(seg "$W/k.elf" NOTE)
[ -n "$note" ] || fail "no PT_NOTE program header"
set -- $note
[ "$(( $2 ))" = "$(( 0x$(sym xen_note) ))" ] || fail "PT_NOTE is at $2, not at xen_note (0x$(sym xen_note))"
[ "$(( $4 ))" = 24 ] || fail "PT_NOTE size is not 24 ($note)"
[ "$(( $1 ))" = "$(( 0x$(sym xen_note) - BASE ))" ] || fail "PT_NOTE file offset $1 is not the note's"
readelf -lW "$W/k.elf" | grep -qE '^ +00 +.*\.note' || fail "the note is not inside the first (RX) PT_LOAD"
desc=$(x64 $(( 0x$(sym xen_note) - BASE + 16 )))
[ "$(( 0x$desc ))" = "$(( 0x$(sym start32) - VMA ))" ] || fail "the note's entry is 0x$desc, want start32 - KERNEL_VMA"
readelf -lW "$W/k.elf" | awk '$1=="LOAD" || $1=="NOTE" { if ($3 != $4) bad=1 } END { exit bad }' \
  || fail "without --load-offset, a p_paddr differs from its p_vaddr"
# --load-offset=KERNEL_VMA: every PT_LOAD and the PT_NOTE at p_vaddr - KERNEL_VMA
# (GNU ld's AT(ADDR(sec) - KERNEL_VMA)); nothing else in the file changes.
"$PXX" --link --freestanding --image-base=$BASE --load-offset=$VMA -e start32 -o "$W/kp.elf" \
  "$W/kboot.o" "$W/kmain.o" > "$W/linkp.log" 2>&1 || { cat "$W/linkp.log"; fail "the --load-offset link failed"; }
n=0; bad=0
while read -r ty off va pa rest; do
  case $ty in LOAD|NOTE) n=$((n + 1)); [ $(( pa )) = $(( va - VMA )) ] || bad=1 ;; esac
done < <(readelf -lW "$W/kp.elf")
np="$n $bad"
[ "$np" = "3 0" ] || { readelf -lW "$W/kp.elf"; fail "with --load-offset, p_paddr is not p_vaddr - KERNEL_VMA on all 3 headers ($np)"; }
[ "$(seg "$W/kp.elf" LOAD | head -1 | awk '{print $3}')" = 0x0000000000100000 ] || fail "the first PT_LOAD's p_paddr is not 0x100000"
ndiff=$(cmp -l "$W/k.elf" "$W/kp.elf" | awk '$1 > 64 + 4 * 56 { n++ } END { print n + 0 }')
[ "$ndiff" = 0 ] || fail "--load-offset changed $ndiff byte(s) outside the program headers"

# ---- controls ------------------------------------------------------------------
# A VLA's code borrows the red zone, so --freestanding refuses it by name
# rather than emitting it.
printf 'long f(int n) { char b[n]; b[0] = 1; return b[0]; }\n' > "$W/vla.c"
"$PXX" --emit-obj --freestanding "$W/vla.c" "$W/vla.o" > "$W/c0.log" 2>&1
grep -q "variable-length array is not supported yet" "$W/c0.log" \
  || { cat "$W/c0.log"; fail "a VLA under --freestanding was not refused"; }
"$PXX" --link --image-base=0x400000 -e start32 -o "$W/k2.elf" "$W/kboot.o" "$W/kmain.o" > "$W/c1.log" 2>&1
grep -q "allocated section '.multiboot' is not one pxx emits" "$W/c1.log" \
  || { cat "$W/c1.log"; fail "without --freestanding, .multiboot was not refused by name"; }
"$PXX" --link --freestanding --image-base=$BASE -o "$W/k3.elf" "$W/kboot.o" "$W/kmain.o" > "$W/c2.log" 2>&1
grep -q "name the entry with -e" "$W/c2.log" \
  || { cat "$W/c2.log"; fail "without -e, the freestanding link did not ask for an entry"; }
"$PXX" --image-base=$BASE test/c_link_freestanding_kernel_main.c "$W/k4" > "$W/c3.log" 2>&1
grep -q "kernel-half base is for --link --freestanding only" "$W/c3.log" \
  || { cat "$W/c3.log"; fail "a compile with a kernel-half --image-base was not refused"; }

"$PXX" --link --load-offset=0x1000 -o "$W/k5" "$W/kmain.o" > "$W/c4.log" 2>&1
grep -q "load-offset: for --link --freestanding only" "$W/c4.log" \
  || { cat "$W/c4.log"; fail "--load-offset without --freestanding was not refused"; }
"$PXX" --link --freestanding --image-base=$BASE --load-offset=0xFFFFFFFF90000000 -e start32 -o "$W/k6.elf" \
  "$W/kboot.o" "$W/kmain.o" > "$W/c5.log" 2>&1
grep -q "larger than --image-base" "$W/c5.log" \
  || { cat "$W/c5.log"; fail "a --load-offset above the image base was not refused"; }

echo "link-freestanding: OK (entry start32, .multiboot first at 0x1000, R_X86_64_32 header words, __executable_start/_edata/_end, .rodata, .note.Xen + PT_NOTE, --load-offset p_paddr, C static data, no SSE/x87, no red zone)"
