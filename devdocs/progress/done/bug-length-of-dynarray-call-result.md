# bug: `Length()` of a dynamic-array function-call result is wrong/crashes

- **Type:** bug
- **Status:** done
- **Track:** A
- **Opened:** 2026-06-23
- **Closed:** 2026-06-24

## Summary

`Length(F(...))` where `F` returns a dynamic array does not evaluate against the
returned array. The inline call result is mis-handled: an empty result segfaults,
a non-empty result yields garbage / 0. Binding the call to a variable first and
taking `Length` of the variable works.

## Minimal repro (no classes, lib/rtl only)

```pascal
program t_len;
type TA = array of Integer;
function MakeArr(n: Integer): TA;
var i: Integer;
begin
  SetLength(Result, n);
  for i := 0 to n - 1 do Result[i] := i;
end;
var a: TA; n: Integer;
begin
  a := MakeArr(3);
  writeln('via var: ', Length(a));   { prints 3  — correct }
  n := Length(MakeArr(3));
  writeln('inline:  ', n);           { prints 0  — WRONG, expect 3 }
end.
```

Build: `pinned -Fulib/rtl t_len.pas t_len` → runs, but `inline: 0`.

With a *managed* element type (`array of AnsiString`) the inline form is worse:
an empty-array return **segfaults**, a non-empty return prints a garbage length
(observed `1566572632`). So the call-result temporary handed to `Length` is not
the real array header — likely an uninitialised / wrong-address temp for a
dynarray function result in argument position.

## Expectation (FPC)

`Length(F())` == `Length(v)` where `v := F()`. The intrinsic must see the same
dynamic-array header the assignment path sees.

## Impact / discovery

Found building `apps/ide/garin/project.pas` (Track B). `TProject.BuildArgs:
TStrArray` returns the compiler argv; `Length(proj.BuildArgs)` crashed. Worked
around in the garin gate (bochan) by binding to a variable first — the natural
idiom — so no library logic is bent. Pure compiler defect.

Related: `bug-length-rejects-non-variable` (done) handled *literal/expression*
args to `Length`; this is the *dynarray call-result* case, which compiles but
miscomputes.

## Workaround in tree (undo when fixed)

User-approved workaround (2026-06-23): bind the dynarray call-result to a
variable before `Length()`. Grep marker: `WORKAROUND(bug-length-of-dynarray-call-result)`.

Site:
- `apps/ide/bochan/main.pas` — `args := rproj.BuildArgs; CheckInt(... Length(args) ...)`.
  Platonic form is `Length(rproj.BuildArgs)` inline.

To undo once this ticket lands: `grep -rn 'WORKAROUND(bug-length-of-dynarray-call-result)'`,
inline each, drop the marker comment, re-run `apps/ide/test.sh` (must stay 92/92).

## Log
- 2026-06-23 — filed (Track B discovery; repro above).
- 2026-06-23 — user approved keeping the var-bind workaround; marked it greppable
  + listed the undo step above.
- 2026-06-24 — FIXED (Track A). Root cause: `Length(F())` lowers the dyn-array
  call result as a value (not an lvalue), and the codegen `else` branch treated it
  as an address — `mov rax,[rax]` read element 0 (gave 0), or wild-derefed for an
  empty managed-element array (segfault). Fix in `ir.inc` (IRLowerAST, tkLength
  arg loop): when the arg is an `AN_CALL` to a proc with `ProcRetIsDynArray`, bind
  the returned handle to a hidden dyn-array local (IsArray, ArrLen=-1, SymDynDepth
  1, ElemType/ElemRecName from `ProcRet*`) and hand its `IR_LEA` to the Length
  codegen — the exact shape a dyn-array variable produces, so every backend's
  existing dyn-array Length path serves it (target-independent, no per-backend
  change). Regression `test/test_length_dynarray_call.pas` (3/3/0/0/4/0) wired
  into `make test`; full `make test` green, self-host byte-identical. Stabilized +
  pinned for Track B. Track B may now undo the bochan workaround
  (`grep -rn 'WORKAROUND(bug-length-of-dynarray-call-result)'`) — left for B's lane.
