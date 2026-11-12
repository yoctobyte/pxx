---
track: A
tags: [C, link]
prio: 20
type: feature
blocked-by: []
summary: "`pascal26 --link --freestanding --image-base=0xFFFFFFFF80100000 -e start32 -o gibux.elf <objs>` links the Gibux kernel, and the image boots under qemu to `Hello from user space` (isa-debug-exit 33, the kernel's own PASS condition; C by pxx, boot.S/entry.S by gas until item 5). New: -e/--entry=, a kernel-half --image-base (link only), .multiboot (first, never collected) and .rodata kinds plus R_X86_64_32 under --freestanding only, ld's linker-defined symbols (__executable_start, etext, _edata/edata, __bss_start, _end/end), and an ElfLnkAlignUp that rounds negative (kernel-half) addresses up. Ordinary --link output is byte-identical to before."
status: done
owner: unassigned
---

# --link --freestanding links a kernel image

Gibux item 4 ([[feature-gibux-kernel-builds-with-pxx]]). The GNU reference is
arch/x86_64/gnu.ld: ENTRY(start32), image at 0xFFFFFFFF80100000, .multiboot
first, then .text and .rodata, .data on a page boundary, and the symbols
__executable_start, _edata and _end.

## What changed (compiler/elfreader.inc, compiler.pas, defs.inc)

- **Entry.** `-e <sym>` / `--entry=<sym>` under --link. Without it,
  `--link --freestanding` uses `_start` if an object defines one and otherwise
  refuses ("name the entry with -e"): there is no runtime to synthesise a
  _start that calls main. **The Gibux Makefile's pxx LINK line needs
  `-e start32`**, the same as gnu.ld's ENTRY(start32).
- **Kernel-half base.** --image-base parses all 64 bits of a hex value and
  accepts 0xFFFF800000000000 and up. Only `--link --freestanding` may use it;
  a compile with it is refused, since the compiler's own writers assume a
  user-half base.
- **ElfLnkAlignUp** rounds by mask for powers of two. `((v + a - 1) div a) * a`
  truncates toward zero, so it rounded a negative (kernel-half) address DOWN.
- **Two section kinds, under --freestanding only:**
  - `.multiboot` (flags A) is laid out first, at base+0x1000, inside the 8 KiB
    a multiboot loader searches. It is a GC root, like KEEP().
  - `.rodata` / `.rodata.*` (flags A) are laid out after .text, in the RX
    segment.

  Without --freestanding both are still refused by name, so the refusal
  controls in tools/elf_reader_vs_readelf.sh keep their meaning. Both are
  relocated in memory before .text is streamed (ElfLnkFillRo).
- **R_X86_64_32**, under --freestanding only, range-checked as unsigned
  32-bit (32-bit boot code: `sym - KERNEL_VMA`).
- **Linker-defined symbols** (ElfLnkDefineLinkerSyms), given an absolute value
  when referenced and not defined by any object: __executable_start, etext,
  _edata/edata, __bss_start, _end/end.
- **Section headers.** .multiboot and .rodata get headers only when they have
  bytes; the symtab's st_shndx goes through an output index map. Ordinary
  links are byte-identical to the previous linker (checked on two programs).

The whole file is congruent (file offset = vaddr - base for both segments),
so a loader that copies it flat from __executable_start - KERNEL_VMA gets the
right image. That is what Gibux's multiboot header asks for.

## Checked

- Gibux kernel fdbadc1: 30 C files by pxx (--emit-obj --freestanding), boot.S
  and entry.S by gcc, linked by this. `qemu -kernel gibux.elf -initrd
  hello.cpio` printed "Hello from user space, a pxx program on Gibux." with
  isa-debug-exit status 33.
- Gibux c3576a5 (plus [[bug-c-a-two-dimensional-function-pointer-array-keeps-only-its-last-dimension]]):
  the same boot, and the kernel's `test-sh` workload (busybox ash running
  tests/sh-basics.sh as init) printed SH-BASICS-DONE with status 33.
- Kernel constraints (item 7): the pxx-linked kernel holds no SSE/x87
  instruction the compiler generated (the only ones are the kernel's own
  fxsave/fxrstor/ldmxcsr), and no access below rsp. Two things changed for
  that: the variadic prologue no longer spills xmm0..7 under --freestanding
  (that was kprintf/ksnprintf), and the two code paths that borrow the red
  zone (alloca/VLA, the Pascal FPU-mask op) are refused under --freestanding
  instead of emitted.
- tools/check_link_freestanding.sh, a Makefile row, links
  test/c_link_freestanding_kernel_boot.s (as) and
  test/c_link_freestanding_kernel_main.c (pxx). It checks by value: the entry,
  .multiboot at offset 0x1000, the five R_X86_64_32 header words, the linker
  symbols, .rodata's R_X86_64_64 words, C static data, no SSE/x87 anywhere
  (a variadic ksum makes that live: the link-only compiler fails it on 8
  movsd), and nothing below rsp. Four controls: a VLA is refused under
  --freestanding;
  .multiboot refused without --freestanding; no -e is refused; a kernel-half
  base is refused for a compile. The 012ccaa92c compiler fails it at the
  --image-base parse.
- tools/elf_reader_vs_readelf.sh: ELF-READER-ORACLE-COMPLETE.
