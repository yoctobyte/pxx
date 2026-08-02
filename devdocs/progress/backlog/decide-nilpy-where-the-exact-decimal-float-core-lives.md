---
track: U
prio: 60
type: decide
summary: "NilPy's float repr needs exact decimal digits + a correctly-rounded strtod. Both exist, in lib/rtl/sysutils.pas — which a BUILTIN unit may not use (builtins sit below the Track B libraries, and pylib dragging sysutils in would link it into every NilPy program). Move the core down into a builtin unit, duplicate it, or relax the layering? Blocks bug-nilpy-float-repr-is-not-pythons-shortest-roundtrip."
---

# Where should the exact-decimal float core live?

- **Type:** decision (Track U) — filed 2026-08-03
- **Blocks:** [[bug-nilpy-float-repr-is-not-pythons-shortest-roundtrip]] (prio
  60). The formatter itself is written and is on that ticket, ready to apply —
  this is the only thing in its way.

## The fork, and how it was reached

Python's `repr(float)` is the SHORTEST decimal string that reads back as the
same double. Producing it needs exactly two primitives:

1. **exact decimal digits** of a double to N significant places (big-integer
   arithmetic — a double's exact expansion runs to 767 digits), and
2. a **correctly-rounded decimal→double parser**, to verify the round trip.

Both already exist and are good: `ExDecDigits` / `ExDecRound` /
`FloatToStrExact` / `StrToFloat` in `lib/rtl/sysutils.pas`. `FloatToStrShortest`
there is already the shortest-round-trip loop; NilPy needs the same loop with
Python's layout rules instead of Pascal's.

The obstacle is layering, not algorithms. NilPy's float printing is
`PyFloatStr` in `compiler/builtin/pylib.pas`, and **a builtin unit may not
`uses sysutils`**. That rule is written down in `compiler/builtin/promoint.pas`,
which reimplemented a bignum core rather than use `lib/rtl/bignum.pas` for
exactly this reason: "a builtin unit that drags sysutils in would defeat the
feature's own size gate — and invert the layering, since builtin units sit
below the Track B libraries."

Measured, so the size claim is not assumed: a trivial `.npy` today does NOT
link sysutils (`PXXDBG=a.ir:FloatToStrExact` on `print(1)` dumps nothing). So
`uses sysutils` in pylib really would add it to every NilPy program.

What `builtin.pas`'s own `FloatToStr` does instead is float arithmetic —
`Trunc`/`Frac`, scaled to 15 decimal places — and that is the direct cause of
all six divergences on the blocked ticket, including the two worst: `1e-20`
printing as `1.000000000000001e-20` (different digits, not fewer) and
`0.1 + 0.2` printing `0.3` (the representation error hidden by rounding, the
one most likely to be read as correct).

## Options

**A — move the core DOWN into a new builtin unit.** `compiler/builtin/exdec.pas`
holding `ExDecDigits` / `ExDecRound` / the exact strtod core; `sysutils` uses it
and keeps its public names as thin wrappers; `pylib` uses it too. One
implementation, correct layering, and every consumer gets the same digits.
- Cost: edits `lib/rtl/sysutils.pas` (Track B) as well as adding a builtin unit,
  so it spans lanes; a new builtin unit needs `make stabilize` + `make pin`.
- Risk: `sysutils`'s own float surface (`Format`, `FloatToStrShortest`,
  `FloatToStrExact`) is widely used and must come out byte-identical.

**B — reimplement the core inside the builtin layer**, as `promoint.pas` did for
bignum. Precedent exists and the layering stays clean.
- Cost: a second exact-decimal implementation. This repo's recurring bug is
  precisely "two readers of one construct that disagree" — a second float
  formatter is that hazard in its most numeric form, and the two would be
  compared by nobody until a value came out wrong.

**C — let `pylib` use `sysutils`.** One line.
- Cost: sysutils in every NilPy binary, and the builtin-below-libraries rule
  broken by the one unit most likely to tempt the next person. If this is
  acceptable it should be written down as a deliberate exception for pylib
  (which is, unlike other builtins, only ever linked by NilPy programs that are
  already large), not left as a silent precedent.

**D — pull sysutils only when a float is actually printed**, the way `Str`/`Val`
are pulled by the bare-name pre-scan.
- Cost: the pre-scan is per-NAME, and "does this program ever print a float" is
  not a name — it is a type. Probably not answerable at that stage.

## Recommendation

**A**, with **C** as the pragmatic fallback if the sysutils edit looks too wide
to do safely in one go. B is the option to avoid: the duplication it creates is
the exact failure mode this codebase keeps paying for, and float formatting is
where a silent disagreement is hardest to notice.

If A: land the builtin unit first with sysutils unchanged (both copies present,
byte-identical output verified), then delete sysutils' copy in a second commit.
That keeps each step's gate small.

## Note

The Python-side formatter is done and measured — the layout rules
(`decpt <= -4 or > 16`, the always-a-point fixed form, the two-digit signed
exponent) are written and on the blocked ticket. Nothing about this decision is
about Python semantics; it is purely about where two numeric routines live.
