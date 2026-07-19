---
prio: 55
type: bug
---

# Undefined field access on an empty record COMPILES silently (reads garbage)

- **Track:** A (shared parser/symtab name resolution; Pascal-facing). Found
  2026-07-18 night by fable-O — surfaced by the optfuzz reducer, whose
  body-stripped candidates kept compiling when they should not have.
- **SILENT WRONG VALUE** class — highest severity per the compat escape rule.

## Repro (current master)

```pascal
type
  TR0 = record
  end;
var
  r0g: TR0;
  x: longint;
begin
  x := r0g.someundefinedfield;   { compiles! x reads 0/garbage }
  writeln(x);
end.
```

`pascal26 lax2.pas out` → `ok:` (35KB binary), prints 0. FPC rejects with
"identifier idents no member". An undefined VARIABLE errors correctly
(`undefined variable`); it is the FIELD path that falls through — likely the
member-resolution failure path defaults to offset 0 / silent-Integer instead
of erroring (compare project_32bit_truthiness "unknown-type silent-Integer
hole" — same disease, field flavor). Also observed in the same reduced file:
a method (`TC0.Calc`) defined for a class that never DECLARED it, and an
undefined local (`v4`) inside such a method body — verify both while in
there; they may share the fallthrough.

## Where to look

Field lookup (FindUField / record member resolution in parser.inc/symtab.inc)
— the not-found branch. Gate: `make test` + self-host + the fuzz reducer's
candidates now FAILING to compile (they became the accidental conformance
probe).

## Log
- 2026-07-19 — resolved, commit 4d46a7ad.
