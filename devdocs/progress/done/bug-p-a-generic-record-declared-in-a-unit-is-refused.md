---
slug: bug-p-a-generic-record-declared-in-a-unit-is-refused
title: "`generic TPointEx<T> = record` in a unit interface: the specialization is never materialised"
track: P
prio: 30
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-08-25
summary: "fpc-testsuite tgeneric77 declares `generic TPointEx<T> = record` with static class methods in a unit's interface and specializes it as `TPointF = specialize TPointEx<single>` in the same interface. Compiled through a driver program that `uses` it, pxx fails; the same template as a CLASS works. Non-class generic templates in a unit interface are the gap."
---

# Repro

`library_candidates/fpc-testsuite/tests/test/tgeneric77.pp`, run through the
conformance runner (which synthesises a driver program for a unit-shaped test):

```
tools/run_pascal_conformance.sh /abs/path/compiler/pascal26 \
    /abs/path/library_candidates/fpc-testsuite/tests/test --only 'tgeneric77.pp'
```

(The absolute paths are not optional — see
`bug-t-run-pascal-conformance-silently-fails-every-test-on-a-relative-compiler-path`.)

The template:

```pascal
generic TPointEx<T> = record
  X, Y: T;
  function Create(const AX, AY: T): TPointEx;
  class procedure Swap(var A, B: TPointEx); static;
  class procedure OrderByY(var A, B: TPointEx); static;
end;

TPointF = specialize TPointEx<single>;
```

Note the self-reference: inside the template, `TPointEx` (unqualified, no `<T>`)
means "the specialization currently being materialised" — as a field type, a
parameter type and a return type. That is the part most likely to be the actual
defect; the class-shaped equivalent already works, so the record path is where
the substitution is not being applied.

# Adjacent, already fixed

`generic TTest<T> = record type TSub = ... end` (tgeneric63/64) was a different
defect — the record body had no nested-`type` arm at all — fixed 2026-08-25 in
`test_record_nested_type_section.pas`. Do not confuse the two: this one is about
the TEMPLATE, that one was about the body's grammar.

# Related and NOT this ticket

`tgeneric76.pp` is the same template shape written as a PROGRAM rather than a
unit; measure it first, because if it also fails the unit-ness is a red herring
and the bug is purely "generic record template with static class methods".

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.

## Resolution (2026-08-25) — the theory in this ticket was WRONG

tgeneric77 goes green with `84728f15a`, which has nothing to do with generic
records or with units. The whole failure was the type ARGUMENT:

```
TPointF = specialize TPointEx<single>;
```

`single` (and `Double`, `Real`, `Extended`, `LongWord`) lexes to its own token
kind, and three separate copies of the "which tokens may stand as a concrete type
argument" list named exactly tkIdent/tkInteger_T/tkBoolean_T/tkChar_T/tkString_T.
Every float was refused as "expected concrete type name" — which is precisely
what this ticket quoted, on the line it quoted, and I read it as a statement
about the record template above it.

Recorded rather than deleted because the mis-reading is the useful part: the
diagnostic pointed at `single`, the ticket blamed `record`, and the difference
was one measurement — `specialize TBox<Double>` against a plain CLASS template,
which takes ten seconds and immediately shows the record is irrelevant. Vary the
shape to find the boundary before writing a cause into a ticket
(devdocs/dev/root-cause-over-microfix.md).

The genuinely-unrelated sibling `tgeneric76.pp` is still red, with a different
failure: the substitution mints `TPointEx$integer` for the self-reference and
leaves the `<integer>` behind it, so the stream reads
`TPointEx$integer<integer>`. Not filed separately yet — it belongs with whoever
next works the Delphi-mode rewriter.
