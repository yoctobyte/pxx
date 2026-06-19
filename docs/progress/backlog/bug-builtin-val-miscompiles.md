# Builtin `Val` mis-lowers — wrong error code + segfault

- **Type:** bug (compiler / builtin)
- **Status:** backlog
- **Owner:** — (track A)
- **Opened:** 2026-06-19 (track B, building lib/rtl/sysutils, on pinned v10)

## Symptom

`Val(s, v, code)` is an intercepted builtin. Calling it produces the wrong
`code` and then **segfaults** on the next call. A user-defined routine with
identical logic under a different name (`MyVal`) works perfectly — so the
intrinsic lowering, not the algorithm, is at fault.

```
Val('1a', v, code)   -> v=0 code=0   (WRONG: code should be 2)  then SEGV next call
MyVal('1a', v, code) -> v=0 code=2   (correct)
MyVal('99', v, code) -> v=99 code=0  (correct)
```

A library can't supply its own `Val` either: the builtin name shadows it (same
interception class as `writeln` / `sysutils`), so the broken builtin is what
actually runs.

## Repro (pinned v10)

```pascal
program t; uses sysutils;        { sysutils declares Val; builtin shadows it }
var v, code: Integer;
begin
  Val('1a', v, code);            { prints code=0; next Val call segfaults }
  writeln(v, ' ', code);
  Val('99', v, code);            { SIGSEGV }
end.
```

`MyVal` (same body, top-level proc, different name) does not reproduce.

## Direction

Fix the builtin `Val` lowering (var-param `code` write + the error path) and/or
allow a library `Val` to override the builtin. Until then, `lib/rtl/sysutils`
ships `StrToInt` / `StrToIntDef` instead and omits `Val`.

## Log
- 2026-06-19 — found on pinned v10 while building sysutils. Worked around by not
  exporting Val; StrToInt/StrToIntDef cover the parsing need.
