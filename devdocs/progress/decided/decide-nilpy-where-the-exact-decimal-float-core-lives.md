---
track: U
prio: 60
type: decide
status: resolved
resolved: 2026-08-03
summary: "NilPy's float repr needs exact decimal digits + a correctly-rounded strtod. Both exist, in lib/rtl/sysutils.pas — which a BUILTIN unit may not use (builtins sit below the Track B libraries, and pylib dragging sysutils in would link it into every NilPy program). Move the core down into a builtin unit, duplicate it, or relax the layering? Blocks bug-nilpy-float-repr-is-not-pythons-shortest-roundtrip."
---

## DECIDED 2026-08-03 — option B: COPY the core into the builtin layer

**User's call.** Not A, not C, not D, and explicitly **copy rather than
reimplement**.

### Why A (move the core down into a shared builtin unit) is out

Not layering purity — **debuggability**. Library source must stay readable and
STEPPABLE: one day you are in a debugger stepping through `sysutils` and you
want to trace straight through it. Option A means stepping into `FloatToStr`
walks you out of `sysutils.pas` into a builtin unit you never asked about, and
an `.inc` extraction is worse — same relocation, and the file stops reading as a
whole. That constraint outranks avoiding duplication.

### Why C and D are out

Name collisions. NilPy's unit scope is flat, which is the reason NilPy cannot
pull `sysutils` in the first place; letting `pylib` do it through the back door
reintroduces exactly what the rule exists to prevent. (Binary size was the
weaker argument; this is the real one.)

### The scope is ~420 lines, not "one function" — measured

| piece | lines |
| --- | --- |
| digits: `ExDecMul`, `ExDecSplit`, `ExDecOfMant`, `ExDecDigits`, `ExDecRound` + `TExDecBuf` / `PXX_EXDEC_LIMBS` | ~113 |
| correctly-rounded parser: `ExDecCmp`, `ExDecBitsToDouble`, `ExDecDoubleToBits`, `ExDecEstimate`, `ExDecNearest`, `StrToFloatDef` | ~304 |

All pure integer arithmetic with no dependencies — genuinely copyable. Accepted
with the number known.

### The parser half is NOT overhead — it fixes a second live bug

`pylib.pyfloat_parse` reconstructs with FLOAT arithmetic and is measurably
wrong. Against pxx's own literals (which are correct — checked separately):

```
float("1e308")                      == 1e308                      -> False
float("2.2250738585072011e-308")    == <the same literal>         -> False
float("0.3333333333333333")         == <the same literal>         -> False
```

So copying the parser lets `pyfloat_parse` become a thin wrapper and makes
`float(str)` correct. Two bugs, one copy.

### And this is not duplication — it is already TRIPLICATION

Three float parsers exist today: `sysutils.StrToFloatDef` (correctly rounded),
`compiler/lexer.inc StrToDoubleBits` (179 lines, its own pure-integer version),
and `pylib.pyfloat_parse` (wrong). Copying the correct one and retiring
`pyfloat_parse`'s body **reduces the number of disagreeing implementations from
two to one**. The lexer's is NOT swept along — its comment claims limitations
that did not reproduce on the inputs tried, so it needs its own measurement.

### Do NOT reimplement via Steele-White

The tempting "smaller" route is Steele-White / Dragon4 midpoints (~40 lines on
top of the digits half, no parser needed). Rejected: it is a NEW float algorithm
in the place where subtle wrongness is hardest to see, and it would not fix
`float(str)`. Copy proven code.

### The round-trip check compares BITS, not doubles

Raised as "never compare floats". The check is asking IDENTITY, not proximity,
so `=` answers it exactly — but it should not be SPELLED as a float comparison:

- it says what it means, so the next reader does not flinch;
- `-0.0`: `StrToFloat('0') = -0.0` is **True**, so sysutils' existing
  `FloatToStrShortest` would accept `'0'` as the shortest form of `-0.0`. A live
  latent hole in the very code being copied;
- `NaN` falls out correctly instead of being permanently unequal to itself;
- it is immune to extended-precision registers. Measured: i386 codegen uses SSE
  for float arithmetic and reaches for x87 only on the 64-bit int conversions,
  so no 80-bit intermediate is live in this path today — but reading the bits
  forces a memory round trip, so it stays immune if that ever changes.

### Semantics: one formatter for `str()` AND `repr()`

There is no friendly-vs-round-trip trade-off to make, and the history is the
argument. Before Python 3.1, `repr` was `%.17g` (round-trips, ugly:
`0.10000000000000001`) and `str` was `%.12g` (friendly, lossy: `0.3` for
`0.1 + 0.2`) — exactly the two requirements in tension. 3.1 adopted shortest-repr
and **made `str` identical to `repr`**, because for every value whose friendly
answer is TRUE, shortest-round-trip already IS the friendly answer (`0.1`, not
`0.10000000000000001`; `3e-05`; `123456789.123`). The only values that print
ugly are the ones that ARE ugly.

The rule: **the default is the shortest string that is still true.** Noise
digits from base conversion are stripped, because a shorter string that still
round-trips proves they carried no information; nothing is stripped when
stripping would change which number you have. Friendliness stays available and
EXPLICIT — `f"{x:.2f}"`, `f"{x:.3g}"` (literally the pre-3.1 `str`), `round()`.

**pxx today is the pre-3.1 `str`** — 15 significant digits — which is why
`0.1 + 0.2` prints `0.3`. Not a choice we made; the behaviour Python abandoned
in 2009 for silently lying.

### Anti-drift: a TEST, not a comment

The duplication's risk is drift, and drift is testable. A permanent differential
test running both implementations over a large sample and asserting identical
output is what turns "we implement this twice, here is why" from a smell into a
checked property — cheap, because a Pascal test reaches `sysutils` and a NilPy
test reaches the copy, with CPython as the oracle for both. Plus a note in each
file naming the other and the reason.

### Follow-up filed, deliberately not solved here

The duplication is a symptom of a general problem — builtin units and `lib/rtl`
cannot share code without either breaking library readability or colliding in
NilPy's flat scope — and more library clashes are expected.
[[decide-builtin-and-library-code-sharing]] records it for later; it is NOT a
blocker for the float work.

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
