---
track: A
tags: [linker, gibux, freestanding, x86-64]
prio: 40
type: feature
blocked-by: []
summary: "pascal26 --link --freestanding keeps .note / .note.* (SHT_NOTE, ALLOC) inputs after .rodata in the RX PT_LOAD and covers them with a PT_NOTE, so a PVH loader finds XEN_ELFNOTE_PHYS32_ENTRY. New --load-offset=<n> writes p_paddr = p_vaddr - n on every PT_LOAD and the PT_NOTE (GNU ld's AT(ADDR(sec) - KERNEL_VMA)); without it p_paddr = p_vaddr as before."
status: done
owner: unassigned
---

# --link --freestanding: PVH note and physical load addresses

Requested by the Gibux session (2026-11-14) for PVH direct boot
(cloud-hypervisor, Firecracker, QEMU microvm). Those loaders read the entry
from a Xen PHYS32_ENTRY note through PT_NOTE and place each segment at
p_paddr. Before this, `--link` refused an allocated `.note.Xen`
("not one pxx emits"), and p_paddr equalled p_vaddr (0xffffffff80100000).

## What changed (compiler/elfreader.inc, compiler.pas)

- A new output kind, `.note` (ELFLNK_K_NOTE), accepted only under
  `--freestanding`. It takes `.note` and `.note.*` inputs of type SHT_NOTE
  with flags A. They go after `.rodata` in the RX segment. GC never drops them
  (KEEP, like `.multiboot`), and relocations apply (the note's `.quad start32 -
  KERNEL_VMA` is an R_X86_64_64). The output section is `.note`, type NOTE,
  and the PT_NOTE's p_align is the largest input alignment.
- `--load-offset=<n>` (hex or decimal, page-aligned). It is refused outside
  `--link --freestanding`, and refused when larger than `--image-base`.
  Gibux: `--image-base=0xFFFFFFFF80100000 --load-offset=0xFFFFFFFF80000000`
  gives LOAD PhysAddr 0x100000, as with the gnu.ld `AT()` change.
- The kind numbering moved (INIT..BSS are now 4..7). Ordinary links write the
  same sections as before, because `.note` appears only when it has bytes.

## Test

`tools/check_link_freestanding.sh` (test-core). The boot half,
`test/c_link_freestanding_kernel_boot.s`, now carries Gibux's `.note.Xen`.
The script checks:

- PT_NOTE is at `xen_note`, 24 bytes, with the right file offset, inside
  the first PT_LOAD;
- the descriptor is start32 - KERNEL_VMA;
- every p_paddr equals p_vaddr without `--load-offset`;
- with `--load-offset=KERNEL_VMA`, all three headers have p_paddr = p_vaddr -
  KERNEL_VMA, the first is 0x100000, and no byte outside the program headers
  changes;
- controls: `--load-offset` without `--freestanding`, and an offset above the
  base, are refused.

The frozen latest compiler fails the script at the link (`.note.Xen` refused).
