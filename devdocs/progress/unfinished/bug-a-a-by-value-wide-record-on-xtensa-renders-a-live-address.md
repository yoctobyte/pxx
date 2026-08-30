---
slug: bug-a-a-by-value-wide-record-on-xtensa-renders-a-live-address
track: A+S
prio: 65
type: bug
status: unfinished
found: 2026-08-30
owner: frankS
---

# A by-value wide record on xtensa renders a live address

> **PARKED — diagnosed to the line, blocked on file contention, NOT half-applied.**
> The tree is clean: the caller-side patch was written, probed, measured, and
> **reverted**, because landing two of the three spots makes the failure *change
> shape* without fixing it. Re-applying is seconds of work
> (`scratchpad/rw/record-caller-side.patch`), and the third spot is one `if` in
> a file frankA is currently in. See **Where it is blocked**.

## Repro — nine lines, and the three symptoms are one bug at three distances

```pascal
type TPlain = record a, b: integer; end;      { 8 bytes }
procedure lone(r: TPlain);                        begin writeln(r.a,' ',r.b); end;
procedure mixedMiddle(x: integer; r: TPlain; y: integer);
                                                  begin writeln(x,' ',r.a,' ',r.b,' ',y); end;
procedure mixedTail(x1,x2,x3,x4: integer; r: TPlain);
                                                  begin writeln(x1,' ',x2,' ',x3,' ',x4,' ',r.a,' ',r.b); end;
```

| call | xtensa | oracle |
| --- | --- | --- |
| `lone(p)` | `1 0` | `1 2` |
| `mixedMiddle(1,p,2)` | `1 1 1 2` | `1 1 2 2` |
| `mixedTail(1,2,3,4,p)` | `1 2 3 4 1 134730429` | `1 2 3 4 1 2` |

Data loss → neighbour corruption → **a live address rendered as a decimal
number**, as the slot that gets read moves further from the one that was
written. arm32 recorded exactly this escalation for the identical defect
(`bug-arm32-record-byvalue-over-4-bytes-abi-gap`); riscv32 hit it as
`bug-riscv32-byval-record-param-one-word`. **riscv32 and arm32 are correct
today; xtensa is the sixth backend, skipped again** — the same sentence as
`ABIParamSlotHoldsValueAddr`, `PXXStrCmp3`, and the frozen-equality guard fixed
an hour ago.

## Three spots, all counting 4 bytes where the type is 8

arm32's ticket is explicit that it is three, and that fixing a subset makes it
worse: *"Fixing the word-count without also widening the param's own frame slot
turned the data loss into active corruption."*

| # | spot | file | status |
| --- | --- | --- | --- |
| 1 | `IR_LOAD_SYM` — a 5-8 byte record VALUE must load BOTH words | `ir_codegen_xtensa.inc` | patch written, **reverted** |
| 2 | the by-value call-arg push loop — push both words | `ir_codegen_xtensa.inc` | patch written, **reverted**; probe-verified as REACHED |
| 3 | **the callee param spill** — store both words and advance `pw` by 2 | **`ir_codegen.inc`** | **not written — blocked** |

## Where it is blocked

`EmitParamSpillsForTarget`'s xtensa arm (`ir_codegen.inc`, ~line 1467) widens
only for `tyInt64 / tyUInt64 / tyDouble`:

```pascal
if ((Syms[idx].TypeKind = tyInt64) or (Syms[idx].TypeKind = tyUInt64) or
    (Syms[idx].TypeKind = tyDouble)) and
   (not Syms[idx].IsRef) and (not Syms[idx].IsArray) then
```

A 5-8 byte `tyRecord` param falls to the `else`, stores **one** word and does
`Inc(pw, 1)`. With spot 2 landed the caller pushes two, so the callee reads one
and **every following parameter shifts by a word** — which is why the middle and
tail rows change value rather than becoming correct.

`ir_codegen.inc` is Track A's and **frankA is working in it right now**
(`perf-a-cache-the-compiled-nilpy-runtime-unit-image`). One `if` needs the
record terms added, plus `Inc(pw, 2)` on that path. Nothing else.

## Why this was probed rather than reasoned

After spots 1 and 2 the minimal repro was **byte-identical to before**, which
reads exactly like "my change did nothing". Reasoning would have gone looking
for a wrong predicate in the arms I had just written. A one-line `Error` probe
in the call-arg arm answered it in one build: **the arm fires.** The caller was
already correct; the callee was the half that had never been visited. Two
minutes of probe against an afternoon of re-reading a correct guard.

## Gate when it resumes

`make compiler/pascal26` to fixedpoint (require the `converged after N round(s)`
line — its absence is the only tell in a tree seeded from outside), the repro
above, `test_arm32_record_byval_wide` against the oracle, and the 129-source
differential for regressions. Wire the test into `test-xtensa` on success.
