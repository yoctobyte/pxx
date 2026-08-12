---
track: A
prio: 55
type: bug
summary: "A Variant argument is TypesCompatible with every scalar parameter, so overload resolution bound whichever candidate was DECLARED FIRST instead of the exact Variant one — a Variant holding 7.5 printed as 7 and one holding a str raised. FPC binds the Variant overload. Surfaced as every NilPy f-string format spec on a list/dict element or unannotated value"
status: done
---

# A Variant argument binds the first COMPATIBLE overload, not the Variant one

- **Type:** bug (silent wrong value) — **Track A** (`compiler/symtab.inc`,
  `MatchProcCall`) — language-agnostic, hits Pascal and NilPy alike
- **Found:** 2026-08-12, differential bug hunting (the standing A+N method):
  a 100-line gradebook program diffed against CPython.

## The Pascal repro, with FPC as the oracle

```pascal
function pick(i: Int64;          const spec: AnsiString): AnsiString;
function pick(const s: AnsiString; const spec: AnsiString): AnsiString; overload;
function pick(d: Double;         const spec: AnsiString): AnsiString; overload;
function pick(const v: Variant;  const spec: AnsiString): AnsiString; overload;

var v: Variant; sp: ShortString;
sp := '6.2f';
v := 7.5;  WriteLn(pick(v, sp));   { FPC: variant     pxx: int }
v := 'hi'; WriteLn(pick(v, sp));   { FPC: variant     pxx: EVariantError }
```

`pick(v, sp)` bound the **Int64** overload and then coerced the Variant to it.

## Why it hid for so long — the second argument decides

`pick(v, s)` with an **AnsiString** second argument is right, and always was:
it is an all-exact call, so Phase 1 of the ladder wins it before compatibility
is ever consulted. Change that one argument to a `ShortString` — merely
COMPATIBLE with the AnsiString parameter — and the whole call falls through to
the compatible phases, where a Variant matches EVERY scalar parameter and the
first candidate in the chain takes it.

So the defect needs two arguments to show: one Variant, and one that is not
exact. Neither alone reproduces it, which is why an overload set that is
exercised constantly could carry it.

## How it reached ordinary NilPy code

NilPy's f-string rewrite emits `pyformat_of(expr, "spec")` and the spec literal
types as `tyString` (ShortString) against `pyformat_of`'s `AnsiString`
parameter — exactly the shape above. `pyformat_of` is overloaded Int64 /
AnsiString / Double / Variant, in that declaration order.

Measured at `ac793cf61`, CPython as the oracle:

| the value being formatted | pxx | CPython |
| --- | --- | --- |
| statically typed float (`plain = 7.5`) | `  7.50` | `  7.50` — agree |
| unannotated parameter `f"{x:6.2f}"` | **`  7.00`** | `  7.50` |
| list element `f"{lst[0]:6.2f}"` | **`  7.00`** | `  7.50` |
| dict element `f"{d['k']:6.2f}"` | **`  7.00`** | `  7.50` |
| any of those holding a **str** | **TypeError raised** | the padded string |

The float rows are the bad ones: **a silent wrong value** — the fractional part
is gone and `7.00` is a perfectly plausible thing for a `.2f` spec to print.
The str rows are loud. An int in a variant was right by accident, because the
Int64 overload is the correct one for it.

Statically typed values were always correct, which is what kept the existing
`test_nilpy_fstring_format_spec` green: every value in it is a literal.

## Root cause

`MatchProcCall`'s ladder (symtab.inc) has a phase for each case where
convertibility must not beat exactness — Phase 1c (a char argument prefers a
string parameter), Phase 1c2 (an integer argument prefers an integer parameter
over a float). The Variant case was missing, and it is the strongest of the
three: `TypesCompatible(<anything>, tyVariant)` is true, so a Variant argument
makes every candidate of the right arity eligible in Phase 1d, and declaration
order decides.

## The fix

**Phase 1c1** in `MatchProcCall`: when any argument is `tyVariant`, prefer a
candidate whose corresponding parameter is `tyVariant`. Every other argument
must still be compatible, so the phase only REORDERS candidates that would all
have matched below — it can never make a call match that did not, and a set with
no Variant candidate is unaffected (that row is in the test).

Runs before Phase 1c2 and Phase 1d, and after the exact phases, so an all-exact
call is unchanged.

## Tests

- `test/test_variant_arg_prefers_variant_overload.pas` — the Pascal repro plus
  the controls: declaration order reversed, a non-Variant argument unaffected,
  the all-exact call unchanged, and an overload set with NO Variant candidate.
  Expectations are FPC 3.2.2's own output.
- `test/test_nilpy_fstring_spec_on_variant.npy` + `.expected` — the NilPy
  surface: list element, dict element, unannotated parameter and attribute, for
  float / str / int, with and without a spec. Expectations from CPython.

## Gate

`make compiler/pascal26` (fixedpoint, 1 round) + `tools/gate.sh quick` GREEN,
plus — because this changes overload resolution for EVERY call in every
frontend, which is the one case a family sweep is actually warranted —
`make test-nilpy` and `make test`.

## Log
- 2026-08-12 — resolved, commit 423094eca.
