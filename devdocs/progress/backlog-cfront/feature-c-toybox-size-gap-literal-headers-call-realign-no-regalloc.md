---
slug: feature-c-toybox-size-gap-literal-headers-call-realign-no-regalloc
track: C
prio: 55
type: feature
status: backlog
created: 2026-11-15
found-by: size root-cause measurement of toybox 0.8.15 (default build, 3ae36d29f5, --function-sections)
tags: [cfront, codegen, size]
blocked-by: []
summary: "pxx's toybox is 1,688,048 bytes, static with its own libc. gcc's is 475,648 (-Os, dynamic glibc), and 2,037,248 stripped if linked static. On toybox's own code pxx emits ~3.6x gcc: 838 shared functions are 838 KB vs 286 KB, a ratio of about 3.3 at every function size; pxx executes 5.0x the instructions. Gap breakdown: codegen density ~743 KB (61%); runtime in the file ~300 KB (25%, only because glibc is a .so for gcc; weak merging works, no duplicates); C string literals ~190 KB (16%), each carrying a 32-byte AnsiString header plus 16-byte alignment (154 KB of headers over 4,805 literals, 35 KB padding; only 5.5 KB is duplicate text). -O2 changes nothing for C (byte-identical sections). Fixes by cost: (1) emit C literals as plain bytes in .rodata, about -190 KB; (2) drop the per-call stack realignment where the frame depth is already known, 18 B x 8,669 calls, up to -156 KB; (3) register allocation for locals (rbp slot traffic 307 KB + movslq reloads 56 KB), the big one, with cheap peepholes meanwhile (branch on the compare instead of setcc/movzb/cmp, -40..55 KB; add/sub $0, -19 KB). Scripts and data: the session scratchpad tbsize/ (gone after the next wipe)."
---

## Item (1) done 2026-11-22 (claude-pxx): C literals are plain bytes

A C string literal is now its bytes and a NUL in data (InternCStr,
emit.inc). It is deduplicated, unaligned and read-only. Before, it was a
pooled managed-string handle with a 32-byte header and 8-byte alignment.
The C AN_STR_LIT lowering yields IR_CONST_DATA for it, so the `+ 8` past
the length prefix is gone as well. Pascal literals are unchanged.

Two consequences, both fixed in the same change:
- In a `--function-sections` object each literal is its own section,
  `.rodata.pxx.cstrN`, flagged A with alignment 1, like gcc's
  `.rodata.str1.1`. Uncut, the literals rode in whichever data section
  preceded them, and the link GC kept that section alive
  (c_link_gc_dead_undefined_ref went red).
- pxx's hosted `--link` now places `.rodata.*` in a read-only `.rodata`
  after `.text`, as freestanding links already did. It used to merge them
  into `.data`. That merge never showed before, because no `.rodata` input
  had survived the GC in the ld cross-check
  (tools/elf_reader_vs_readelf.sh, which now pins `.rodata` at pxx's
  address too). A C `const` object in a hosted executable is therefore
  read-only now, as with gcc.

Measured with the same sources, before and after:

| program | before | after |
|---|---|---|
| 900-literal test program, data | 61168 | 19802 |
| ...code | 95501 | 91117 |
| Rainyday esp32s3 kernel (text+data) | 1129560 | 1111196 (-18.4 KB) |
| Rainyday pc kernel (text+data) | 1804689 | 1758999 (-45.7 KB) |

Both Rainyday kernels boot in QEMU as before. Toybox was not re-measured.

Test c_string_literal_plain_bytes (gcc-checked on x86-64 and i386, the same
on aarch64, arm32, riscv32 and wasm32) covers indexing, deref, sizeof,
concatenation, embedded NULs, dedup, global tables and returned literals.
Row c_litraw26_sec checks the object layout.
