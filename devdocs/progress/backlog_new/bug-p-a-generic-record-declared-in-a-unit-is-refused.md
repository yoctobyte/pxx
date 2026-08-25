---
slug: bug-p-a-generic-record-declared-in-a-unit-is-refused
title: "`generic TPointEx<T> = record` in a unit interface: the specialization is never materialised"
track: P
prio: 30
type: bug
blocked-by: []
status: backlog_new
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
