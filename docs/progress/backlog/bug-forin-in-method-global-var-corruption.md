# `for-in` inside a method corrupts a dyn-array global declared after it

- **Type:** bug (compiler / symbol table)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20 (found while fixing `bug-for-in-implicit-self-field`)
- **Relation:** pre-existing latent bug, independent of the for-in resolver
  work — confirmed to reproduce on the HEAD compiler *before* the for-in
  implicit-Self-field change. Surfaced because the new for-in test exercises a
  method-body for-in followed by a global dyn array.

## Symptom

A method whose body contains a `for-in` loop, combined with a dynamic-array
**global** variable declared *after* some other globals, makes that global
unresolvable at parse time:

```text
pascal26:22: error: undefined variable (arr)
```

The error fires at the first *use* of the global (e.g. `SetLength(arr, …)`),
not at its declaration — the var simply isn't registered/visible.

Minimal repro (fails on HEAD, with or without the implicit-Self-field for-in fix):

```pascal
program forin_global_corruption;
{$define PXX_MANAGED_STRING}
type
  TObj = class function F: Integer; end;
var g: array of Integer;
function TObj.F: Integer;
var v: Integer;
begin
  Result := 0;
  for v in g do Result := Result + v;   { for-in inside a method body }
end;
var
  o: TObj;
  i, acc: Integer;
  arr: array of Integer;                 { declared AFTER other globals }
begin
  o := TObj.Create;
  SetLength(g, 2); g[0] := 3; g[1] := 4;
  Writeln(o.F);
  SetLength(arr, 3);                      { error: undefined variable (arr) }
  arr[0] := 100; arr[1] := 20; arr[2] := 1;
  acc := 0; for i in arr do acc := acc + i;
  Writeln(acc);
end.
```

## Observations (narrowing)

- Parity-sensitive: adding one more local to the method (so its local + the
  for-in's synthetic index temp reach a different count) makes the error vanish.
  Declaring `arr` *before* the scalar globals also sidesteps it.
- Not for-in-shape specific to fields: a plain-variable for-in over a global
  (`for v in g`) inside the method triggers it just as a field for-in does.
- No for-in in the method body → never reproduces, regardless of local count.

This points at the for-in desugar's anonymous index `AllocVar('', tyInteger)`
(BuildForInArrayLoop) being created during method-body parse and throwing off a
symbol-count / scope-base boundary that later global-var registration relies on.
The corruption is in symbol-table accounting, not in for-in itself.

## Acceptance

- The minimal repro compiles and prints `7` then `121`.
- A regression test (method-body for-in + trailing dyn-array global) in
  test-core; ideally also the cross suites.

## Log
- 2026-06-20 — Opened. Found while landing `bug-for-in-implicit-self-field`;
  confirmed pre-existing by reproducing on the HEAD compiler built without the
  for-in change. The for-in implicit-field test orders its globals to dodge this
  bug so the two issues stay decoupled.
