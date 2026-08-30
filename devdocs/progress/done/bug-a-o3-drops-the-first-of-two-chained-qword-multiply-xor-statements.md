---
prio: 50
track: A+O
type: bug
blocked-by: []
summary: "Eight-line repro: two chained `h := h * 31 xor qword(v)` statements over qword. At -O3 the first statement's result is discarded — the value entering the second is the THIRD variable's value, not the first statement's — so the program prints 222 instead of 635218. -O0, -O1, -O2 and FPC at -O0 and -O2 all agree on 635218. Boundary established on four axes: the two-statement chain is required, the multiply in the second statement is required, qword (unsigned) is required (all-int64 is clean), and the -O3 answer is independent of the middle operand, which is what shows the first statement is dropped rather than miscomputed. Found by the pasmith multi-unit rung; units turned out to be irrelevant."
status: done
owner: frank-optimize-b4
---

# `-O3` drops the first of two chained qword `* 31 xor` statements

- **Type:** bug (optimizer — wrong code, silent) — **Track A**, work-tag **O**.
  Filed 2026-08-30 by the Track T agent. T files, T does not fix.

## Repro — eight lines, no units, no records, no functions

```pascal
program min3;
{$mode objfpc}{$Q-}{$R-}
var a, b, c: longint; h: qword;
begin
  a := 661; b := 0; c := 7;
  h := qword(a) * 31 xor qword(b);
  h := h * 31 xor qword(c);
  writeln(int64(h));
end.
```

```
pxx -O0 = 635218    pxx -O1 = 635218    pxx -O2 = 635218    pxx -O3 = 222
fpc -O0 = 635218    fpc -O2 = 635218
```

At `5dd25e789`, compiler binary sha256 `41e452a55913`, self-host fixedpoint
verified at HEAD before measuring.

## What -O3 actually does

`222` is not noise, it is arithmetic. Working backwards: `X * 31 xor 7 = 222`
gives `X = 7` — which is `c`. So the value entering the **second** statement is
`c`, not the first statement's result (20491). **The first statement is
discarded and `h` is loaded with the wrong symbol.**

Confirmed by making the middle operand non-zero: with `b := 5`, `-O2` and FPC
move to 635317 and **`-O3` still prints 222**. The `-O3` answer does not depend
on `b` at all, which is what distinguishes "the first statement is dropped" from
"the first statement is miscomputed".

## Boundary — four axes, each measured

| variation | result |
| --- | --- |
| single statement, no chain | **clean** — the chain is required |
| second statement without `* 31` (`h := h xor qword(c)`) | **clean** — the multiply in stmt 2 is required |
| all `int64`, no `qword` casts | **clean** — the unsigned type is required |
| `b := 5` instead of `0` | still 222 — the result is independent of the dropped statement's operands |
| record fields / nested record / cross-unit record / enum operand / inside a function | all still reproduce — none of these are involved |

The last row matters for how this was found: it came out of the pasmith
`--units 2` rung as `pxx-self_unitrec`, and **units, records and nesting were all
irrelevant**. The discovery vehicle was not the subject; the signature name is the
statement kind at the first checkpoint that diverged, which is a discovery
coordinate rather than a cause.

## Suspect, stated as a suspect

`ir_codegen.inc:6402` is gated
`(OptLevel >= 3) and (op = tkStar) and (IRKind[left] = IR_LOAD_SYM)` — a multiply
whose left operand is a symbol load, which is exactly the shape of `h * 31` in
the second statement, and the neighbouring `-O3` fusions at 6258/6431 are the
same family. **This is where I would look, not a conclusion.** I did not bisect
the `OptLevel >= 3` sites because frankA holds `ir_codegen.inc`/`emit.inc` under
a live Track A lock, and a temporary diagnostic edit is still a concurrent edit.

## Relationship to `bug-a-o3-alone-computes-a-different-result-for-a-nested-case-statement`

Possibly the same root, **not established either way.** Both are `-O3`-only,
four-oracles-to-one, silent, and both diverging programs are dense in `qword`
arithmetic. But that ticket's repro is a 77-line nested `case` and this one is
eight lines with no `case` at all, so they are not the same *shape*. If they do
share a root, this repro is by far the better handle and fixing it should be
tried first — re-run seed 91162 afterwards to find out. **They are filed
separately because merging two findings on a suspected common cause is how one of
them stops being tracked when the other is closed.**

## Why prio 50

Higher than the `case` ticket's 45 for one reason: the repro is eight lines, so
the cost of acting on it is small and it may close both. Still bounded by `-O3`
being the free tier — nothing ships built at it, `-O2` is the proven default —
but this is silently wrong integer arithmetic from a chain any hash or checksum
loop would produce, and it blocks promoting the pass at fault to `-O2`.

## Acceptance

The eight-line program prints 635218 at `-O3`, and seed 91162 from the sibling
ticket is re-checked to record whether it was the same defect.

## Resolution (2026-08-30, frank-optimize-b4)

**The pass at fault is `-O3` store→reload elimination**
(`feature-opt-store-reload-elimination`), and the defect is not in the pass's
idea but in the way it decides where to apply it.

The pass marks an `IR_LOAD_SYM` as redundant when the immediately preceding
top-level statement stored that very symbol and **nothing at all was emitted in
between**, so rax still holds the value. It decides that with
`IRFirstEvaluated`, a **hand-maintained mirror of `IREmitNode`'s operand-order
guard chain** — and the mirror is missing an arm. `-O3`'s **W1 slice 9**
(`ir_codegen.inc`, "both subtrees proven pure → park the RIGHT value in the
scratch register and evaluate it first") reverses evaluation order; the mirror
walks the LEFT subtree unconditionally and answers "the leaf load of `h`".

So for `h := h * 31 xor qword(c)` the load of `h` was marked redundant, the
emitter evaluated `qword(c)` into rax first, and the load emitted **nothing** —
`EmitReExtendRax` on a qword is a no-op. The result is `(c * 31) xor c` = 222.

**The four axes T measured are each explained by that mechanism, which is the
check that this is the right cause and not a plausible one:**

| axis | why the mechanism needs it |
| --- | --- |
| two-statement chain | the mark requires the preceding statement to store `h` |
| `* 31` in statement two | the `-O1` imm-fold arm is what makes `IRFirstEvaluated` walk *down* to the leaf load instead of stopping at "cannot say" |
| `qword` casts | a cast lowers to a binop, so the right operand is not a leaf; the leaf-right arms *above* slice 9 do not take it. All-`int64` never reaches slice 9 — which is exactly why it was clean |
| answer independent of the middle operand | statement one's result is never read: rax holds `qword(c)`, so nothing of statement one survives |

### The fix — verify the premise where it is used, do not predict it better

The obvious repair is to add the missing arm to `IRFirstEvaluated`. That fixes
this shape and leaves the design defect in place: **two models of one decision,
kept in sync by hand, where the emitter is the authority and the mirror is a
copy.** The mirror's own comment says "MUST MOVE TOGETHER WITH
IREmitMachineCode's arms" — the instruction was there, and it was not followed,
which is what a hand-sync requirement gets you.

So the mark is still a prediction, but it is now **checked at the point of use**:

- `ReloadRaxCodeLen` is set to `CodeLen` at the top of every IR node's iteration
  in `IREmitMachineCode`, so within a statement it is "CodeLen when this
  statement began emitting".
- The redundant-load arm elides only when `CodeLen = ReloadRaxCodeLen` — i.e.
  when the load really is the first thing this statement emits.

That expression *is* the pass's stated premise ("nothing at all was emitted in
between"), evaluated against what the emitter actually did rather than against a
model of what it would do. A mirror that drifts again now costs a **missed
optimisation**, which is what the mirror's comment already claimed was the worst
case.

### Measured

| check | result |
| --- | --- |
| eight-line repro, `-O0/-O1/-O2/-O3` | **635218** (fpc -O2: 635218) |
| same with `b := 5`, all levels | **635317** |
| **seed 91162** (the `case` ticket), `-O0/-O2/-O3` | **16452949249337348755** |
| self-host fixedpoint | `converged after 1 round(s)`, sha256 `46dbc0e5f751` |

**Cost of the check, on `compiler.pas` at `-O3`: 19,941 marks, 1 declined.**
That ratio is the whole story of why this survived: the mirror was wrong once in
twenty thousand, and the one time it was wrong it produced a plausible number.
The single decline in the compiler's own `-O3` build (`sym imm8`, 24 bytes
already emitted) was a live wrong-code site.

### And it closes the sibling

Seed 91162 now agrees with all four oracles, so
`bug-a-o3-alone-computes-a-different-result-for-a-nested-case-statement` was the
same defect. **That is a measurement, not the assumption the two tickets were
deliberately kept apart to avoid** — the acceptance criterion written into this
ticket is what turned the question into one command.

### Regression

`test/test_opt_store_reload.pas` gains section 6 (both repro shapes) and the
Makefile rows assert the **values** 635218 / 635317, never "the two `-O` levels
agree" — they agreed at 222 as well. A row also asserts the emit-time refusal
actually fires (`PXXDBG=a.reload:*` now prints `DECLINED` lines), because a
guard that never declines cannot be shown to work.

### Not done here

The pass stays on `-O3`. Promotion to `-O2` is a separate decision and wants
the full gate plus a measured win, not a fixed bug.

## Log
- 2026-08-30 — resolved, commit 10c869750.
