---
track: P
prio: 40
type: bug
blocked-by: []
status: open
owner: frankS
found-by: frankS
created: 2026-09-08
summary: "RESOLVED 2026-09-09: there is no generic Explicit fallback in fpc at all -- toperator91 declares `Explicit(...): ShortString` and never calls it on ANY row. An Explicit operator serves a frozen-string destination only at its OWN capacity; a cast matching none of them is not an explicit conversion and retries the IMPLICIT lookup, where the generic exemption is real; nothing there refuses. toperator91 now matches fpc byte for byte, exit 0. This ticket's central caution was WRONG and is corrected in the resolution: it said a fallback must always exist, and fpc keeps none -- with only a non-matching Explicit declared it answers `Illegal type conversion`, where pxx ran the wrong operator. The segfault the old fallback guarded is closed by a diagnostic instead, narrowed to frozen-string destinations so a record cast to a pointer or another record still reinterprets. The named control had to change because its row 3 WAS this bug: it asserted the generic Explicit conversion while noting fpc refuses that cast; re-aimed to assert the implicit retry, with the refusal split into its own fixture."
---

# An explicit cast with no capacity match falls back to the wrong conversion operator

```pascal
{ toperator91.pp, reduced }
class operator TTest.Explicit(const a: TTest): ShortString;  { pxx picks this }
class operator TTest.Implicit(const a: TTest): ShortString;  { fpc picks this }
...
s40 := TString40(t);            { no Explicit operator has capacity 40 }
if ImplicitShortString <> 1 then Halt(3);
```

An explicit cast writes its destination, so capacity discriminates among the
`Explicit` operators — that half landed 2026-09-07 and `TString80(t)` /
`TString90(t)` reach their own operators. What is unsettled is the FALLBACK when
no Explicit operator has the destination's capacity. pxx takes the generic
Explicit one (`OpConvResultCapRank`'s generic-fallback rank, which exists
because removing it segfaulted); fpc takes the generic Implicit one.

## Why it was split out rather than fixed alongside

It changes the explicit-cast fallback path, and that path has a live hazard with
a dated cost: `s40 := TString40(t)` with only a ShortString conversion declared
once fell through to a raw record-to-string store and SEGFAULTED, where fpc uses
its ShortString overload. `OpConvResultCapRank` in `symtab.inc` carries that
note. Any change here must keep a fallback — the question is only WHICH operator
it lands on, never whether there is one.

## The control already exists

`test/test_conversion_operator_result_capacity_is_part_of_its_identity.pas` pins
the explicit-cast behaviour that must survive, and `toperator91.pp` is the row
that goes green. Take them together.

## Resolved 2026-09-09 — there is no generic Explicit fallback at all

The rule is not "prefer the generic Implicit one". It is:

1. An `Explicit` operator serves a frozen-string destination **only at its own
   capacity**. No generic exemption.
2. A cast matching none of them is **not an explicit conversion**, and retries
   the IMPLICIT lookup — where the generic exemption is real and a bare
   `ShortString` result does serve every destination.
3. Nothing there either → **refuse**.

Read off toperator91 rather than inferred: `ExplicitShortString` is never
incremented **anywhere** in that program, including the two rows whose capacity
no Explicit operator has. fpc prints `ShortString Implicit` for both. An
operator that is declared and never called on any row is a stronger statement
than "the fallback picks the other one".

pxx now prints all eight lines and `ok`, exit 0, byte-identical to fpc 3.2.2.

### This ticket's central caution was wrong

> *Any change here must keep a fallback — the question is only WHICH operator
> it lands on, never whether there is one.*

**fpc does not keep one.** With only a non-matching `Explicit` declared and no
`Implicit`, fpc refuses:

```
only_exp.pp(13,10) Error: Illegal type conversion: "TTest" to "TString40"
```

pxx ran the wrong operator and printed a result. So the segfault that the
generic-Explicit fallback was protecting against is closed **by a diagnostic**,
which is what fpc does and is strictly better than reaching a conversion fpc
would not use. The refusal is narrowed to frozen-string destinations: a record
cast to a pointer or to another record is a legitimate reinterpret and still
falls through. A string destination has no sane raw reading — the length byte
is the first byte of whatever the record holds.

### The control had to change, and it was the same mechanism

`test_conversion_operator_result_capacity_is_part_of_its_identity.pas` row 3
asserted that `TS40(t)` reaches the generic ShortString **Explicit**
conversion, and said in its own comment that fpc refuses that cast — kept as a
deliberate leniency because the alternative then was the segfault.

That leniency **is** this bug. One rule cannot serve both, so row 3 was
re-aimed rather than deleted: the file gained an `Implicit ShortString`
operator, and row 3 now asserts the retry landing on it (`toSSimp`, never
`toSS`). All three rows are now byte-identical to fpc, where the file
previously diverged on one. The refusal case moved to
`test_conversion_operator_no_capacity_match_is_refused.pas`.

**The pair is the point.** One row shows the retry landing on the generic
Implicit conversion; the other shows the refusal when there is nothing to retry
with. Neither alone separates a working retry from a refusal that swallows
every cast — which is the shape this change could most easily have had.

Ambiguity refuses rather than picking: with two sized results and no generic,
fpc does not choose (`OpConvImplicitResultRank`'s fifth measured row), and
silently taking one is the accepted-invalid shape this family keeps producing.
