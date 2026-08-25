---
track: P
prio: 58
type: feature
blocked-by: []
status: backlog
summary: "`class helper for TC` is refused with `Expected: :, but got: for` while `record helper for T` and `type helper for T` both work — the third spelling of one concept was never wired. fpc compiles and runs it; the helper method sees the class's fields through Self."
---

# `class helper for <class>` is not accepted

Found 2026-08-22 by an FPC differential sweep over language shapes
(`fpc -Mobjfpc -O1` 3.2.2 vs pxx `f73eca492`).

## Repro

```pascal
type
  TC = class
    x: Integer;
  end;
  TCH = class helper for TC
    function Twice: Integer;
  end;
function TCH.Twice: Integer; begin Result := x * 2; end;
...
  c := TC.Create; c.x := 21; Writeln(c.Twice);
```

fpc prints `42`. pxx:

```
Expected: :, but got: for (Kind: 20, Line: 6)
pascal26:6: error: unexpected token
```

## Why this is small, and where it goes

The concept is already implemented **twice** in `pasparser_decl.inc`:
`record helper for <type>` (~line 5005) and `type helper for <type>` (~line
5022, FPC's alternate spelling), both building a helper-marked class-like entry
with `UClsHelperTk` / `UClsHelperRec` and dispatching methods on the target with
`Self` as parameter 0. `class helper` is the same shape with two differences
worth getting right rather than guessing:

- the target is a **class**, so `Self` is the object POINTER by value, not the
  target by reference the record/type helper passes;
- fpc allows only one active helper per type per scope, and a class helper may
  extend a class it does not own (that is the point of it) — the existing helper
  lookup must resolve through the class's ancestry, not just an exact match.

Per `normalise-dont-special-case.md`, add the arm to the SAME machinery rather
than a third parser path, and check the two existing spellings still agree
afterwards.

## Gate

`make compiler/pascal26` + a test covering a class helper reading and writing
the target's fields, a helper on an ancestor reached through a descendant, and
the record/type helper rows kept as controls + `tools/gate.sh quick`.
