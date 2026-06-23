# bug: ParamStr/ArgStr result not usable inline (needs a string variable)

- **Type:** bug (Track A — IR codegen)
- **Status:** backlog
- **Found:** 2026-06-23, solitaire GUI `--smoke` arg parsing
- **Severity:** low-medium (every `ParamStr(i) = '...'` must go through a temp)

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
