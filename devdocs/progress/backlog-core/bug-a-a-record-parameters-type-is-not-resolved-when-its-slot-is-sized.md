---
track: A
prio: 40
type: bug
blocked-by: []
summary: "AllocParam decides a by-value record parameter's slot size from RecSize(LastTypeRecId), and LastTypeRecId is REC_NONE for 41 of the 52 record parameters in compiler.pas. RecSize(REC_NONE) is the 8-byte fallback, so the `RecSize(..) <= 8` test that chooses between an inline record slot and a pointer slot is a CONSTANT TRUE for those 41 — the branch's comment describes a decision it is not making. Not a miscompile: every later answer is <= the 8 it reserves, so the slot is over-allocated by up to 4 bytes on a 32-bit target and never under-read. What it costs is that the rule cannot be reasoned about, and it is the input half of the ticket that renamed ParamSize."
status: open
owner: ""
---

# A record parameter's type is not resolved when its slot is sized

- **Type:** bug (symbol table / frame layout) — **Track A**.
- Found 2026-09-01 by frankA while closing
  [[bug-a-paramsize-and-allocparam-disagree-about-a-5-8-byte-byvalue-record]].
  That ticket says *"AllocParam is the one that is right"*. It is right, but
  **by the clamp rather than by the test** — which is what this ticket records.

## Measured, not inferred

A scratch `WriteLn` in `AllocParam`, printing `Syms[SymCount].RecName`,
`LastTypeRecId` and `RecSize` for every `tk = tyRecord` parameter, then
compiling `compiler/compiler.pas` with it:

```
52 record parameters
41 with recid = 0 (REC_NONE)  -> RecSize answers its 8-byte fallback
11 with a real id (9, 18, 22, 25, 26) -> RecSize 16, 40, 56
```

The 11 are what makes this a finding rather than a broken probe: the population
CAN contain a resolved id, so the 41 are a real distribution and not a
zero-shaped instrument failure.

The consequence, in `AllocParam`:

```pascal
if (tk = tyRecord) and not isRef and not isArray and (RecSize(LastTypeRecId) <= 8) then
```

For 41 of 52 that reads `8 <= 8`. The comment beside it explains how a
genuinely by-value record is stored inline while a record forced to by-ref by
size takes a pointer slot — a distinction the test is not drawing for those
parameters.

Same shape on a 32-bit target (arm32, `TARGET_PTR_SIZE = 4`), from the same
probe on a four-record test program — every one of the four came through with
`recid=0 RecSize=8`, including a 4-byte record and a 16-byte one:

```
SCRATCH param r recid=0 lasttyperecid=0 RecSize=8 isRef=FALSE slotword=4 valuesize=8
```

## Why it is not a miscompile, checked rather than assumed

The fallback reserves `max(8, TARGET_PTR_SIZE)`. Every answer `ParamValueSize`
can give once `RecName` IS resolved is `<= 8`:

| real record | resolved answer | reserved | |
| --- | --- | --- | --- |
| `RecSize <= 8`, by value | `max(RecSize, TARGET_PTR_SIZE)` ≤ 8 | 8 | fits |
| `RecSize > 8` (by-ref by size) | `TARGET_PTR_SIZE` (4 or 8) | 8 | fits |
| by-ref (`var`/`const`/`out`) | `TARGET_PTR_SIZE` | 8 | fits |

So the slot is over-allocated by up to four bytes on a 32-bit target and is
never under-read. That is why this is prio 40 and not higher, and why it is
filed rather than fixed inside a rename commit: the fix changes FRAME LAYOUT,
which is the widest blast radius in the compiler, and it deserves its own
before/after byte-comparison across all five targets.

## Where to look

`LastTypeRecId` is the parser's "record id of the type just parsed" global.
Whatever writes it is not writing it (or has already reset it) on the path that
declares a parameter — note `Syms[SymCount].RecName := LastTypeRecId` in
`AllocParam` records the same REC_NONE, and the backends' spill code reads
`Syms[idx].RecName` LATER and gets the right answer, so **something fills it in
after AllocParam**. Find that writer; the question is whether the resolution can
be moved before the slot is sized, or whether the slot size has to be revised
when it lands.

`ProcParamRecId[procIdx * MAX_PROC_PARAMS + i]` is the other carrier the
backends use and is correct at spill time; it is the obvious candidate for what
the sizing should have consulted.

## What a fix must assert

- the same probe reports **0** parameters with `recid = 0` where the source
  names a real record type, over `compiler/compiler.pas` — and reports the same
  11 resolved ids it does today, so the fix widened the population rather than
  silencing the counter
- emitted binaries for a program with 4-, 6-, 8- and 16-byte by-value record
  parameters are compared before/after on **all five targets**; a frame-layout
  change that is correct will still move bytes, so the assertion is on the
  program's OUTPUT, not on byte-identity
- `test/` gains a by-value record parameter of each of those four widths, run
  on the four cross targets — the existing coverage is one width
- self-host fixedpoint, which is itself a strong control here: `compiler.pas`
  has 52 record parameters and its own frame layout would move
