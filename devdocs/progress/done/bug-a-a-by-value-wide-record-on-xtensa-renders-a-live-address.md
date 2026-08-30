---
slug: bug-a-a-by-value-wide-record-on-xtensa-renders-a-live-address
track: A+S
prio: 65
type: bug
status: done
found: 2026-08-30
owner: frankS
---

# A by-value wide record on xtensa renders a live address

> **RESOLVED.** All four spots landed together. Both ABIs now match the x86-64
> oracle on every shape probed, `test_arm32_record_byval_wide` is wired into
> `test-xtensa`, and the 129-source differential went **100 -> 101 matching with
> zero programs regressed** (windowed 50 -> 51). Compiler sha `1f24e6cd3989`.
>
> **It was four spots, not three.** The ticket said three and named them; a
> shape-varying probe found the fourth after the first three were green. What
> follows keeps the original three-spot analysis intact and adds the fourth
> below it, because the reason the count was wrong is the reusable part.

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
| 1 | `IR_LOAD_SYM` — a 5-8 byte record VALUE must load BOTH words | `ir_codegen_xtensa.inc` | **landed** |
| 2 | the by-value call-arg push loop — push both words **and apply the even-word pad** | `ir_codegen_xtensa.inc` | **landed** |
| 3 | the callee param spill — store both words and advance `pw` by 2 | `ir_codegen.inc` | **landed** (bounded grant) |
| 4 | `IR_LOAD_MEM` — a record-RETURNING call used directly as an argument | `ir_codegen_xtensa.inc` | **landed** — *not in the original analysis* |

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

## RESOLUTION

Landed as one change, compiler sha `1f24e6cd3989`, `converged after 1 round(s)`.

| measurement | before | after |
| --- | --- | --- |
| `lone(p)` | `1 0` | `1 2` ✓ |
| `mixedMiddle(1,p,2)` | `1 1 1 2` | `1 1 2 2` ✓ |
| `mixedTail(1,2,3,4,p)` | `1 2 3 4 1 134730429` | `1 2 3 4 1 2` ✓ |
| `test_arm32_record_byval_wide` | DIFF | MATCH, both ABIs |
| 129-source differential, Call0 | 100 match / 7 diff | **101 / 6**, zero lost |
| 129-source differential, windowed | 50 match / 55 diff | **51 / 54**, zero lost |

The match-set delta was computed as a set difference in both directions, not
from the totals — a +1 that is really a +2/-1 looks identical in a count.

### Two things this ticket got wrong, and both were caught by measuring

**1. The blocked spot 3 was written as dead code first.** The obvious guard —
`sz > 4` where `sz` was already in scope as `ParamSize(idx)` — compiles,
self-hosts, and never fires, because `ParamSize` answers the SLOT-LAYOUT
question via `ABIParamSlotIsPointer`, which holds `tyRecord` unconditionally.
So `sz` is `TARGET_PTR_SIZE` (4 here) for *every* record regardless of width.
I wrote a comment asserting `sz` "asks the record's real width rather than
assuming it"; that sentence was reasoning, and it was false. The repro came back
byte-identical and the false comment was the only reason the arm looked right.
arm32 and riscv32 spell it `RecSize(Syms[idx].RecName)` a few dozen lines up in
the same procedure — the fix was to copy the two backends that already had the
rule, not to invent a third spelling. `ParamSize` and `AllocParam` genuinely
disagree here; filed separately as
[[bug-a-paramsize-and-allocparam-disagree-about-a-5-8-byte-byvalue-record]].

**2. It was four spots, not three, and only a shape-varying probe found it.**
With spots 1-3 green, `lone` and `tail` were correct and `mixedMiddle` was wrong
in a *new* way (`1 2 2 1` for `1 1 2 2`) — the caller had packed the record at
words 1-2 while the callee read 2-3 and took word 4 for `y`, i.e. the callee
applied the even-word pad and the caller did not. That was spot 2 missing
`XtensaPadTo64Xtensa`. Then a deliberately widened repro — 4-byte record, 5-byte
record, two records in a row, 5th and 6th parameter positions, forwarding a
record parameter onward, and a record-RETURNING function called directly as an
argument — turned up exactly one surviving failure: `inner(mk)` printed `7 0` on
Call0 and `7 6` (a stale register) on windowed. The producer node there is
`IR_LOAD_MEM`, not `IR_LOAD_SYM`, so widening `IR_LOAD_SYM` could not cover it.
riscv32 carries that arm with the identical comment; xtensa had never had it.

**The generalisation, and it is the same one this repo keeps re-deriving:** the
repro in a ticket describes ONE shape of the defect, and a fix measured only
against that repro is a fix sized to the repro. Varying the shape cost about ten
minutes and moved the count from three spots to four. Had I stopped when the
ticket's own three rows went green — which is what "the ticket said three" makes
tempting — `inner(mk)` would have shipped broken, and it is precisely the shape
(a record-returning function used inline) that a real program reaches for.
See `devdocs/dev/root-cause-over-microfix.md`.

### Sixth-backend note

All four spots are rows arm32 and riscv32 already carried. That is now the
*fifth* xtensa defect tonight with the same signature — a rule the other
backends have and xtensa was skipped for — after `ABIParamSlotHoldsValueAddr`,
`PXXStrCmp3`, the frozen-string equality guard, and `SPECIAL_IN`. The standing
explanation is in `scratchpad/why.md` and holds here too: **the target with no
working oracle is the target that keeps the bug.** xtensa has an oracle now, and
this is what it is for.

## Gate as run

`make compiler/pascal26` to fixedpoint — `converged after 1 round(s)`, sha
`1f24e6cd3989`, confirmed different from `pinned` — the repro above, the widened
shape probe, `test_arm32_record_byval_wide` against the x86-64 oracle in both
ABIs, the 129-source differential in both ABIs for regressions, and
`tools/gate.sh quick` (this touched a shared Track A file, so the optional
quick gate was run rather than skipped). `test_arm32_record_byval_wide` is wired
into `test-xtensa`, compared against the x86-64 oracle rather than a literal
transcript, since the point of the row is agreement with the other backends.

## Log

- 2026-08-30 — resolved, commit PENDING-COMMIT.
