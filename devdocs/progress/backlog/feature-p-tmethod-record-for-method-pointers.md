---
track: P
prio: 35
type: feature
blocked-by: []
status: backlog
summary: "`TMethod` is undefined — `var m: TMethod` fails with `unknown type: TMethod`. It is the standard system record `record Code, Data: Pointer end` that names the two halves of a `procedure of object` value, and the documented way real code takes a method pointer apart or builds one."
---

# `TMethod` is not defined

Found 2026-08-22 by an FPC differential sweep over language shapes
(`fpc -Mobjfpc -O1` 3.2.2 vs pxx `f73eca492`).

## Repro

```pascal
type TProc = procedure of object;
var m: TMethod; p: TProc;
begin
  m.Code := nil; m.Data := nil;
  p := TProc(m);
  Writeln('ok ', Ord(m.Code = nil));
end.
```

fpc prints `ok 1`. pxx:

```
pascal26:3: error: unknown type: TMethod
```

## What it is

In FPC/Delphi `TMethod` is declared in `system` as

```pascal
TMethod = record
  Code, Data: Pointer;
end;
```

— the layout a `procedure of object` value already HAS. pxx already represents
method pointers as a `{Code, Data}` pair (`SymElemProcSig`, the `AN_CALL_IND`
method-pointer path), so this is naming an existing layout, not inventing one.

Real code uses it to compare two event handlers, to detach one, or to build a
method pointer from a raw address — all of which currently have no spelling.

## Shape of the fix

Declare it where the other built-in system records live so it needs no `uses`,
and make the casts `TMethod(someEvent)` / `TProc(m)` legal in both directions
(the value is already the same two words, so the cast should be a retag, not a
conversion). Check `@obj.Method` fills `Code` and `Data` the way fpc does before
asserting anything about the values.

## Gate

`make compiler/pascal26` + a test that takes a real method pointer apart,
rebuilds it, calls through the rebuilt value, and compares two handlers for
equality (against the fpc oracle) + `tools/gate.sh quick`.
