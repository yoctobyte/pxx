---
track: N
prio: 35
type: bug
blocked-by: []
summary: "pyeval's tokenizer refuses an exponent float literal (`1e3`, `2E-3`) — `float exponent literals not supported in M1`, compiler/builtin/pyeval.pas:1882. It surfaced when the lambda/closure body reconstruction started carrying float literals at all (2026-09-12): the body is rebuilt as TEXT and re-lexed by pyeval, so `lambda: 1e3` would have compiled and died at RUN time. It is refused at COMPILE time instead, by name, so nothing moved later than it already was — that refusal is the current behaviour and this ticket is to replace it with support. Scoped to the INTERPRETED path only: a lifted/compiled lambda body never reaches pyeval and handles exponents fine. A SECOND question is in the same tokenizer and should be answered in the same visit, but is NOT the same bug and must not be silently folded in: the fraction is accumulated digit-by-digit against `scale := scale * 0.1` (pyeval.pas:1873-1879), which is not the same arithmetic as StrToDoubleBits, so an interpreted literal and a compiled one can differ in the last place. Rank the exponent gap on the refusal; rank the accumulation on evidence that a real program cares, per the F-lane rule."
---

# pyeval cannot read an exponent float literal

`compiler/builtin/pyeval.pas:1881` sees `e`/`E` after a number and calls
`TokError('float exponent literals not supported in M1')`.

## How it was found, and why it is not urgent

It is not reachable from ordinary Pascal or from a compiled lambda. It became
reachable on 2026-09-12, when `PyLambdaTokText` learned to render a `tkFloat` at
all — the lambda body is reconstructed as text from its token span and handed to
pyeval, so the literal's spelling has to survive a round trip.

Rather than ship a compile-to-run-time regression, the exponent spelling is
refused at compile time with its own message:

```
error: Nil Python: an exponent float literal (1e3) is not supported in an
interpreted lambda/closure body yet — write it in plain decimal
```

That arm is reached ONLY while building the pyeval text, so a lifted body is
unaffected.

## Why not normalise the spelling instead

`.5` -> `0.5` IS done, because the two spellings are the same decimal and no bits
move. An exponent is not that: turning `1e300` into plain decimal is a 300-digit
string, and turning `2E-3` into `0.002` is a re-rounding. The normalisation that
is exact by inspection was taken; this one needs the tokenizer.

## What a fix must not do

Do not implement the exponent by a `for i := 1 to exp do fv := fv * 10` loop —
that compounds rounding and would turn a loud refusal into a quiet wrong value,
which is strictly worse than today.
