---
track: A
prio: 50
type: bug
summary: "The .debug_line program emits DW_LNS_advance_pc with a NEGATIVE delta, encoded as unsigned ULEB128. Each one adds 2^32 to the address register, so every row after the first backward step is unreachable — 25911 of 76894 rows (34%) in the compiler's own -g build, i.e. the whole upper fifth of the binary has no usable line info."
status: done
owner: claude-A@opus5
---

# `.debug_line` advances the PC backwards, and the address register wraps

- **Type:** bug (DWARF emission) — **Track A** (`elfwriter.inc`, the line-table
  program). Pre-existing; **not** introduced by
  [[bug-compiler-selfdebug-lines-index-expanded-source]], which is what turned
  it up.
- **Found:** 2026-08-03, while verifying the include-marker fix.

## The measurement

`make pxx-debug`, then read the raw line program:

```
$ readelf --debug-dump=rawline compiler/pascal26-debug
  [0x0003f8df]  Advance PC by 135 to 0x8d2bfe
  [0x0003f8e4]  Advance PC by 4294967161 to 0x1008d2b77
```

`4294967161` is `0xFFFFFF79` — **-135** in two's complement. The emitter wanted
to step *backwards* 135 bytes, back to `0x8d2b77`, a row it had already passed.
`DW_LNS_advance_pc`'s operand is an **unsigned** LEB128, so the consumer adds
4294967161 instead and the address register carries into bit 32.

It never recovers. Every subsequent row is offset by 2^32, and each further
backward step adds another:

```
rows with a sane (<2^32) address : 50983   addresses 0x420087 .. 0x8d2bfe
rows with a corrupted address    : 25911   low 32 bits 0x8d2b77 .. 0xaa252a
distinct high dwords in those    : 1, 2, 3, ... 104   (one per backward step)
```

So **34% of the line table describes addresses that do not exist**, and the
damage is contiguous: everything the linker placed above `0x8d2bfe`. In the
compiler that is `pyparser.inc` and the whole main program body.

## What it looks like from the outside

This is the "plausible wrong answer" failure mode, not a crash — gdb reports
something, and the something is wrong:

```
(gdb) info line PyClassCreateExpr
No line number information available for address 0x966f49 <PyClassCreateExpr>
(gdb) break compiler/pyparser.inc:1279
Breakpoint 1 at 0x6800950162: compiler/pyparser.inc:1279.   # address is fiction
(gdb) bt
#6  ... in ParseProgram () at compiler/parser.inc:29840      # correct
#7  ... in Pascal26 () at compiler/asmdisasm_x64.inc:99      # wrong file entirely
```

Frame #7 is the main program body in `compiler.pas`. gdb names
`asmdisasm_x64.inc` because that is the last row with a *believable* address —
the rows that actually cover the main body are all in the wrapped region.

Confirmed present in a `-g` build from `stable_linux_amd64/default/pinned`
against HEAD sources (25882 corrupted rows), so it long predates the include
markers.

## Why a row goes backwards

The rows are emitted in AST/source order, and emitted code is not laid out in
that order — an out-of-line branch target, a routine's epilogue, anything the
codegen places out of sequence gives a row whose address is below its
predecessor's. DWARF requires addresses within one **sequence** to be
non-decreasing, so as soon as source order and address order disagree, the
program is invalid.

## The fix (two candidates)

1. **Sort rows by address within the sequence** before emitting. Correct by
   construction and keeps one sequence, but rows must carry (addr, file, line)
   and be sorted rather than streamed.
2. **Close and reopen the sequence on a backward step**: emit
   `DW_LNE_end_sequence`, then `DW_LNE_set_address` at the new address. Local
   to the emitter — the check is `if newAddr < curAddr then ...` — and DWARF
   explicitly allows many sequences per CU. Cheaper to land; produces more
   sequences (104 here) but every row stays reachable.

Option 2 is the contained one and is what the shape of the emitter suggests;
option 1 is the tidier table. Either way the invariant to assert afterwards is
"no row's address is below its predecessor's within a sequence" — cheap to
check in the emitter and worth keeping as an assertion under `-g`.

## Acceptance

- `readelf --debug-dump=rawline` on `compiler/pascal26-debug` shows **no**
  `Advance PC` operand above the binary's size, and no decoded row address
  above 2^32.
- `info line PyClassCreateExpr` resolves; `break compiler/pyparser.inc:<line>`
  gives a real address; a backtrace from a breakpoint deep in the parser names
  `compiler/compiler.pas` for the main-body frame.
- Self-host fixedpoint byte-identical (nothing changes without `-g`).

## Resolution 2026-08-03 (claude-A@opus5)

Option 1 (sort), not option 2 (split the sequence) — measurement made the choice
cheap. The 104 backward steps displace at most 5389 bytes of code (median 1615),
so the rows are already sorted apart from small local inversions and a **stable
insertion sort** over the four parallel `DwarfRow*` arrays is linear in practice.
Splitting into 104 sequences would have cost each sequence's last row its
coverage; sorting costs nothing and produces the table DWARF actually wants
(a line program maps address -> line, so address order IS the correct order).

Stability is load-bearing: several rows legitimately share an address and the
first of them carries `prologue_end`. Shifting rather than swapping keeps it
first.

`BuildDwarfSections` (`elfwriter.inc`), immediately before the line program.

### Verified

| | before | after |
| --- | --- | --- |
| rows with an address >= 2^32 | 25911 of 76894 | **0** |
| `Advance PC` operands above 2^31 | 104 | **0** |

```
(gdb) info line PyClassCreateExpr
Line 4003 of "compiler/pyparser.inc" ...     { was: no line number information }
```
— and `pyparser.inc:4001` is `function PyClassCreateExpr;`, 4003 its first
statement, so the row is right and not merely present.

```
(gdb) bt
#6  ... ParseProgram () at compiler/parser.inc:29882
#7  ... Pascal26 () at compiler/compiler.pas:932      { was: asmdisasm_x64.inc:99 }
```
— `compiler.pas:932` is the `ParseProgram;` call. The whole backtrace is now
correct top to bottom, which it has never been.

`tools/gate.sh quick` GREEN (self-host fixedpoint byte-identical — nothing
changes without `-g` — testmgr quick, FPC seed canary).

## Log
- 2026-08-03 — resolved, commit 3efc30537.
