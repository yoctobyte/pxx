---
summary: "RESOLVED 2026-11-20: on x86-64 SysV, a C struct of 16 bytes or less comes back in rax/rdx (or xmm0/xmm1). The caller stored each eightbyte at full register width into a hidden temp that is only as big as the record, so a 4-byte struct wrote 8 bytes and the upper half landed on the next local. csmith seed 1120027 (and 7 more seeds, two buckets): a discarded `func_1()` returning a 4-byte union turned main's print_hash_value into 32767. The store now uses the record's size: 8/4/2/1-byte pieces for the GP class, and movss for an SSE piece of 4 bytes or less."
type: bug
track: C
prio: 75
status: done
created: 2026-11-20
found-by: claude-dupwt (csmith sitting, seeds 1120000..1120199)
owner: claude-dupwt
tags: [c-frontend, codegen, x86-64, abi, csmith]
blocked-by: []
---

## Symptom

csmith MISCOMPILE_VS_GCC on x86-64, 8 of 200 seeds:
1120027/040/064/124 (bucket A) and 1120051/057/083/099 (bucket B).
pxx printed the verbose per-variable hash dump that gcc did not print. The
checksum itself matched. In every case `print_hash_value` read 32767 right
after `func_1();`, a call whose struct/union result was discarded.

cvise reduced it to:

```c
struct U0 { unsigned f1 };
struct U0 func_1() {}
void main() { int k; int print_hash_value = 0; func_1(); transparent_crc(g_2, "", print_hash_value); }
```

## Cause

`IREmitSysVRetStore` (compiler/ir_codegen.inc) wrote each returned eightbyte
with `mov [rax+8*i], r11|rcx` (and `movsd` for SSE), whatever the record's
size. The hidden destination is `AllocVar('', tyRecord)`, so it is only
RecSize bytes. For a 4-byte struct, the high 4 bytes of rax went into whatever
the frame layout put next, here main's `print_hash_value`. SysV leaves the
bytes of the register past the struct undefined; at -O0 they were the high half
of a stack address, 0x00007fff.

It only shows when a 4-byte local is packed right after the temp: one `int k;`
added or removed and the clobber falls into padding. That's why a hand-written
repro failed at first and why printf instrumentation hid it.

## Fix

`IREmitSysVRetStore(destNode, n, c0, c1, sz)` stores each eightbyte at
min(8, sz-8*i) bytes:
- GP: 8, or 4+2+1 pieces with `shr` between them, all as literal lines
  (`IREmitSysVGpPiece`/`IREmitSysVGpShift`) so the gate's static assembler pass
  reads every one.
- SSE: `movss` when the piece is 4 bytes or less, otherwise `movsd`.

Both callers pass `RecSize(ProcRetRecId[...])`.

## Test

`test/c_struct_ret_in_regs_stores_its_own_size.c` (test-core, rows `c_sretregs26`
and `c_sretregs26o2`) covers 20 shapes from 1 to 16 bytes, GP and SSE, with no
padding. Each is checked twice:
- discarded, with the reproducing `int pad; int sentinel;` layout;
- kept and byte-hashed.

The expected output is gcc's. The latest compiler before the fix gives 10 bad
sentinel lines; after the fix the output equals gcc at -O0 and -O2. aarch64
already matched at -O0/-O2.
All 8 csmith seeds now match gcc's checksum and output.
