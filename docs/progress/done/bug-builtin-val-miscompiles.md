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

## Resolution (2026-06-19) — FIXED

Two bugs in the `Val` intrinsic lowering (parser.inc ~5865), both target-independent:

1. **1-char source literal → segfault.** `Val('5', ...)` parses `'5'` as a Char;
   the builtin's first param is a string, so the Char was passed where a string
   pointer is expected and `Length(s)`/`s[i]` dereferenced garbage. The intrinsic
   skipped the Char→string-literal coercion a normal call applies. Now promotes a
   Char literal arg to an `AN_STR_LIT`. (This was the "segfault on next call" —
   actually the success path on a 1-char input.)
2. **narrow `dest` overrun.** The integer `Val` writes an Int64 (8 bytes) through
   `var v`; a `var v: Integer` (4 bytes) destination — the common case — was
   overrun, clobbering the neighbouring `code` (hence `code` wrong / stale) and
   the stack. The intrinsic now marshals a sub-8-byte ordinal dest through a
   hidden Int64 temp and truncates into the real destination afterwards.

Validated: `Val('5')`, `Val('55')`, `Val('1a')` (code 2), `Val('x')` (code 1),
signed, leading spaces, Int64 dest, float dest — all correct, no crash, with both
`var v: Integer` and `var v: Int64`. Test: `test/test_val_builtin.pas` in
test-core. Self-host + cross-bootstrap byte-identical.
