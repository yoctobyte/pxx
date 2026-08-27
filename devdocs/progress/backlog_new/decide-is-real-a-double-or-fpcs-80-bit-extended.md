---
track: U
prio: 30
type: decide
blocked-by: []
keep-open: "a permanent dialect decision about the default float type's PRECISION; it changes printed digits and arithmetic results for every program that writes a bare `Real`, so it must not be settled by an agent on its own"
status: backlog
owner: ""
summary: "`writeln(3.14159)` prints ` 3.1415899999999999E+000` in pxx and ` 3.14158999999999999993E+0000` in FPC, because pxx's Real is a 64-bit Double and FPC's is the x87 80-bit Extended. Making them agree means implementing an 80-bit float type; keeping them apart means declaring the difference permanent. Both are defensible and neither is a bug."
---

# Is `Real` a Double, or FPC's 80-bit Extended?

Filed 2026-08-27 while clearing `tools/fpc_diff_probe.sh`'s unfiled `known`
rows. The row `real-default` had been tagged `known` since it was written with
no ticket behind it — the probe's own header calls that "a lie with a cost" —
and on inspection it is not a bug anybody forgot to file. It is an unmade
decision.

## The divergence

```pascal
begin writeln(3.14159); end.
```

| | output |
|---|---|
| FPC 3.2.2 (x86-64) | ` 3.14158999999999999993E+0000` |
| pxx | ` 3.1415899999999999E+000` |

Two differences at once, and only the first is the decision:

1. **Precision.** FPC's `Real` on x86-64 is `Extended`, the x87 80-bit type
   (64-bit mantissa). pxx's is `Double` (53-bit mantissa). The digits differ
   because the values differ.
2. **Exponent width.** FPC prints a 4-digit exponent for Extended and 3 for
   Double, so the field width follows from (1) rather than being its own call.

## Why it is a decision and not a task

Both answers are defensible, and the cost is real either way:

- **Keep Double.** `Extended` is x87-only: it does not exist on aarch64, arm32,
  riscv32 or xtensa, all of which pxx targets. FPC itself falls back to Double
  for `Extended` on those targets, so "match FPC" is not even well defined
  across the fleet — matching on x86-64 would make pxx's own targets disagree
  with each other, which is a worse property than disagreeing with FPC. This is
  the status quo, and the argument for it is the cross-target one.
- **Implement Extended.** It is what portable FPC source *observes* on the
  desktop target, and a numeric program ported from FPC gets different answers
  under pxx today, silently. That is the strongest argument on the other side:
  the difference is not a formatting one.

The scope if the answer is "implement it" is not small: an 80-bit type needs
x87 codegen (the SSE2 path cannot express it), its own `Str`/`Val` rounding,
`SizeOf` = 10 with 16-byte alignment, and a decision for every non-x87 target
about what `Extended` means there.

## What is NOT being asked

Whether `Double` is correctly implemented — it is, and `tools/fpc_diff_probe.sh`
agrees with FPC on every Double-typed case. This is only about what the bare
name `Real` (and an unsuffixed float literal) means.

## Once answered

- **"Double is permanent"** → retag the probe row `bydesign` with the
  cross-target reason above, and add that reason to `docs/language/types.md`.
  That file already says `Real` is "an alias of `Double`", so the *behaviour* is
  documented; what is missing is that this DIFFERS from FPC on x86-64 and that
  the difference is deliberate. A porter reading only the type list has no way
  to learn that their numbers will change.
- **"Implement Extended"** → this becomes a Track A feature ticket with the
  four sub-parts listed above, and the probe row stays `known` pointing at it.
