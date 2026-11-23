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

## `add/sub $0` done 2026-11-23 (claude-pxx)

The x86-64 IR_FIELD arm emits nothing for a field at offset 0, and the
imm-fold binop arm emits nothing for `+ 0`, `- 0`, `| 0` and `^ 0`. The
Rainyday pc kernel had 3058 `add $0x0,%rax` and 74 `sub $0x0,%rax`; it
now has none, and its text is 12.8 KB smaller (1716903 -> 1704131). It
boots as before. Rows c_fz026 (the values, against gcc) and c_noaddzero26
(the count). Still open here: (2) the per-call realignment and (3) register
allocation. (2) needs a static rsp depth, and x86-64 codegen does not track
one: pushes come both from the text assembler and from raw EmitB bytes.

## `&&`/`||` on 0/1 operands done 2026-11-23 (claude-pxx)

CMakeTruthy no longer wraps an operand that is already 0/1 (a comparison,
`!`, or an and/or of two such) in `!= 0`. The Rainyday pc kernel had 2242
`setcc; movzx; cmp 0; setne; movzx` doubles. Text, same source:

| kernel | before | after |
|---|---|---|
| pc | 1704131 | 1628910 (-75 KB) |
| esp32s3 | 1108956 | 1044536 (-64 KB, 5.8%) |

Both boot as before. Test c_logical_operand_already_boolean, gcc-checked on
x86-64, i386, aarch64, arm32, riscv32 and wasm32 and at -O2; rows on x86-64
and aarch64.

## Negated short-circuit conditions done 2026-11-23 (claude-pxx)

IRLowerCondJump branches on x and y for `(x && y) == 0` (a C `!(x && y)`,
and every `for` test of an `&&`/`||`, built as `if (cond == 0) break`),
instead of storing the `&&` in a temp. pc text 1628910 -> 1622846
(-6.1 KB), esp32s3 1044536 -> 1041804 (-2.7 KB); both boot. The ~1400
bool store/reload pairs left are value uses (`return a && b;`, `x = a < b`)
and need the register-allocation item. Test c_negated_short_circuit_branch.

## `xor eax, eax` for al = 0 done 2026-11-23 (claude-pxx)

Before a C call x86-64 set al (vector registers used, for variadic
callees) with `mov eax, 0`, 5 bytes, before 10935 calls in the Rainyday pc
kernel. `xor eax, eax` is 2; the flags it clobbers are dead before a call.
pc text 1622846 -> 1589910 (-32.9 KB); boots. Test
c_vararg_vector_count_zero, row c_vacnt26.

Correction: row c_noaddzero26 (72d13651f7) counted in an executable, which
objdump cannot disassemble (no section headers), so it printed 0 whatever
the code. It and c_vacnt26 now count in an `--emit-obj` object; both fail
with the compiler from before their fix (545 and 585) and pass now.
