---
prio: 50
track: A+O
type: bug
blocked-by: []
summary: "Eight-line repro: two chained `h := h * 31 xor qword(v)` statements over qword. At -O3 the first statement's result is discarded — the value entering the second is the THIRD variable's value, not the first statement's — so the program prints 222 instead of 635218. -O0, -O1, -O2 and FPC at -O0 and -O2 all agree on 635218. Boundary established on four axes: the two-statement chain is required, the multiply in the second statement is required, qword (unsigned) is required (all-int64 is clean), and the -O3 answer is independent of the middle operand, which is what shows the first statement is dropped rather than miscomputed. Found by the pasmith multi-unit rung; units turned out to be irrelevant."
status: new
owner: ""
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
