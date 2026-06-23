# `const`/value open-array of a managed element loses its length (High = -1)

- **Type:** bug (Track A — open-array ABI / managed elements)
- **Status:** DONE — 2026-06-23.
- **Owner:** —
- **Opened:** 2026-06-23 (found by a TUI integration test, Track B)
- **Relation:** sibling of the fixed `bug-var-open-array-fixed-arg-length`
  (that one was **var/out** open arrays; this is **const/value** + a **managed**
  element type).

## Symptom

A `const` (or value) open-array parameter whose element type is **managed**
(`AnsiString`) receives a wrong implicit length when the argument is a fixed
array: `High(a)` comes back as **-1** (length 0). The element type matters — the
same code with `array of Integer` is correct.

- same compilation unit: `High(a) = -1`, so `for i := 0 to High(a)` runs zero
  iterations — the routine silently does nothing.
- across a unit boundary the bad length is worse than -1 (garbage / positive):
  `a[i]` then reads out of bounds and **segfaults**. This is how it surfaced —
  `menu.MenuDraw(x,y, const items: array of AnsiString, selected)` crashed when
  `selected` was a variable (the marshalling of the trailing scalar plus the
  managed open array corrupts the fat pointer); with a literal `selected` it
  happened to survive.

## Minimal repro

```pascal
program oas;
procedure P(const a: array of AnsiString);
var i: Integer;
begin
  writeln('high=', High(a));
  for i := 0 to High(a) do writeln(a[i]);
end;
var arr: array[0..2] of AnsiString;
begin
  arr[0] := 'x'; arr[1] := 'y'; arr[2] := 'z';
  P(arr);            { prints high=-1 and nothing else; expected high=2, x y z }
end.
```

Control — `array of Integer` is fine:

```pascal
function P(const a: array of Integer; n: Integer): Integer; begin P := High(a) + n; end;
{ P(arr, 5) = 7, P(arr, v) = 3  -- High(a)=2, correct }
```

## Likely cause

The implicit high/length companion for a `const`/value open array of a managed
element type is not materialised from a fixed-array argument (it reads as -1).
The fix for var/out (`bug-var-open-array-fixed-arg-length`) did not cover the
const/value path for managed elements; compare the two and the data-pointer vs
length companion for a fixed-array lvalue with a managed element type.

## Impact

Any library taking `const items: array of AnsiString` (menus, tables, option
lists) is unusable — silently empty same-unit, a crash cross-unit. Found writing
`test/lib_tui_app.pas`. Worked around in Track B by keeping the menu widget to
the pure `MenuNavigate` logic and leaving item rendering to the caller (a plain
indexed loop, no managed open-array parameter); `MenuDraw` was removed until this
is fixed — no library code bent to a wrong shape.

## Acceptance

- The repro prints `high=2` and `x y z`; the cross-unit menu form does not crash.
- Self-host fixedpoint + existing open-array tests stay green.

## Fix log

- 2026-06-23 — DONE (3d2b5b8). The value/const open-array copy-in path
  (TryStaticToOpenArray, ir.inc) excluded managed element types, so a `const
  array of AnsiString` fed a fixed array got no header'd temp -> bare address ->
  `High` read garbage [P-8] (= -1; positive/garbage across a unit -> segfault).
  Fix: allow `tyAnsiString` elements through the copy path. The existing
  byte-copy of the element handles is correct for a CONST (read-only, borrowed)
  parameter: the caller's array keeps the references and the hidden temp does not
  over-release them (verified: a 5000-call cross-unit loop + use-after-call leaves
  the strings intact — no crash, no over-release). Managed-field RECORD elements
  stay excluded (need per-field ARC). Repro now prints `high=2` + `x y z`; the
  trailing-scalar-after-open-array form (the cross-unit crash) is correct. Test
  `test/test_const_open_array_managed.pas`, FPC oracle-matched. make test +
  cross-bootstrap byte-identical.
- NOTE (minor, pre-existing, both managed + non-managed): the per-call open-array
  copy temp's dyn-array block is not freed (a small transient leak per call site);
  correctness is unaffected. A follow-up could free the temp block at call return
  (the var/out path has the same shape).
