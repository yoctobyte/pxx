---
prio: 52  # auto — blocks the GL demo (sole demos-dashboard FAIL); order-dependent symtab bug
---

# Class-typed property WRITE mis-parses ("Expected: [") depending on uses order

- **Type:** bug (frontend — shared symbol resolution / property-setter lookup)
- **Track:** A (`parser.inc` / `symtab.inc` property + unit-scope resolution).
  Filed from Track B/E (GL demo triage) — hand off, do not fix under B/E.
- **Status:** done
- **Owner:** opus-a

## Symptom
Writing a **class-typed property** through its setter fails to parse with
`Expected: [, but got:  (Kind: 63, Line: N)` — the parser, on seeing the
property name, expects an array `[` index. It is **order- and unit-graph
sensitive**: the exact same statement compiles when the uses clause is smaller
or reordered. Live at pinned v197 AND at HEAD.

## Minimal repro (fails)
```pascal
program glg;
uses controls, stdctrls, forms, glarea, sysutils;   { sysutils LAST }
var a: TGLArea; f: TForm;
begin
  a := TGLArea.Create(nil);
  f := TForm.Create(nil);
  a.Parent := f;         { <-- pascal26:7: Expected: [, but got: (Kind 63) }
  writeln('ok');
end.
```
`TControl.Parent` is a plain `property Parent: TControl read FParent write
SetParent;` (lib/pcl/controls.pas).

## What flips it green (all verified)
- **Reorder** `sysutils` earlier: `uses sysutils, controls, stdctrls, forms,
  glarea` → compiles.
- **Fewer units:** `controls, sysutils` / `controls, stdctrls, sysutils` /
  `controls, forms, glarea, sysutils` all compile; adding `stdctrls` to the
  4-unit set is what tips it over. So it is a **cumulative unit-graph**
  threshold, not one specific unit.
- **Read instead of write:** `p := a.Parent;` compiles fine.
- **Int-typed property write:** `a.Left := 5;` compiles fine.
- So the break is specifically **writing a property whose type is a class**,
  in a large-enough / wrongly-ordered unit graph.

## Read
The `Expected: [` strongly implies the identifier `Parent` resolved to a
symtab entry the parser believes is array-indexable — i.e. a **symbol-id
collision / stale scope entry** introduced by unit load order, that only the
setter-write path consults (the getter-read path resolves the property
correctly). Likely in the property-assignment lowering's symbol lookup or a
unit-scope table that isn't order-invariant. None of the trigger units
(controls/stdctrls/forms/glarea/sysutils) declare a default or indexed
property, so it is not a real `Items[]`-style default-array clash — the
collision is internal.

## Impact
`examples/gl/triangle.pas` is the **sole `make demos` FAIL** (it uses exactly
`gtk3, controls, stdctrls, forms, extctrls, glarea, gl_c, sysutils, math` and
writes `Area.Parent := Form1`). Left idiomatic/unchanged per the no-workarounds
policy — resolving this ticket unblocks it directly. Any real program with a
broad widget uses graph that assigns `.Parent` (i.e. every non-trivial GUI app)
can hit it.

## Gate
`make test` + self-host byte-identical. Add a `.pas` regression mirroring the
repro (a class-typed property write behind a multi-unit uses graph);
`examples/gl/triangle.pas` compiling under `make demos` is the end-to-end check.

## Log
- 2026-07-11 — resolved, commit dcfbac67.
