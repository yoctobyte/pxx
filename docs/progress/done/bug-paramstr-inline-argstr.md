# bug: ParamStr/ArgStr result not usable inline (needs a string variable)

- **Type:** bug (Track A — IR codegen)
- **Status:** done
- **Found:** 2026-06-23, solitaire GUI `--smoke` arg parsing
- **Closed:** 2026-06-23
- **Severity:** low-medium (every `ParamStr(i) = '...'` must go through a temp)

## Resolution (2026-06-23)

Front-end only. Inline `ParamStr(i)` (the expression-form `tkArgStr`) now
synthesizes a hidden FROZEN string temp, copies argv[i] into it via the existing
2-arg ArgStr path (`EmitArgvToString` — a frozen-buffer write, no managed
release, so the temp needs no nil-init), and yields the temp via the
`AN_STR_FROM_CHAR` (side-effect + read) pattern. So `ParamStr(i)` is usable
directly in comparisons / arguments, not only as an assignment RHS. (The
`AN_STR_FROM_CHAR` lowering now statement-marks its Left so the call-shaped
side-effect is emitted; a store-shaped Left like `String(c)` is unaffected.) A
frozen temp avoids the managed-temp-created-mid-parse nil-init crash landmine.

Also fixed the separate-observation segfault: `EmitArgvToString` /
`EmitArgvToStringManaged` now bounds-check the index against argc (`[initial_rsp]`)
and return '' (frozen) / nil (managed) for an out-of-range index, instead of
dereferencing a NULL/past-end argv slot.

Verified byte-identical to FPC: `ParamStr(1) = 'foo'`, `Length(ParamStr(1))`,
no-args `ParamStr(1)` -> '' (was a segfault). Gate: `make test` (self-host
byte-identical) + FPC oracle. Closes bug-paramstr-inline-argstr.

## Symptom

Using `ParamStr(i)` directly in an expression fails at codegen:

```pascal
program t;
begin
  if ParamStr(1) = chr(120) then writeln(1) else writeln(0);
end.
```

→ `error: ArgStr expects a string variable in IR codegen`.

Control — assigning to a string variable first compiles:

```pascal
var s: string;
s := ParamStr(1);
if s = chr(120) then writeln(1) else writeln(0);
```

## Expected

`ParamStr(i)` (→ ArgStr) should be usable as a normal string r-value in
expressions, function arguments, comparisons — not only as the RHS of an
assignment to a string variable. The codegen helper appears to require its
result land in a named string variable.

## Notes

- Worked around in solitaire by `arg := ParamStr(1)` then comparing; per the
  no-workaround policy, revert to the inline form once fixed.
- Separate observation (maybe its own bug): `ParamStr(i)` for an out-of-range
  index (no such argument) segfaults at runtime instead of returning ''. Worth a
  bounds check.
