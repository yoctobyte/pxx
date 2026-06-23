# feature: class variables (`class var`)

- **Type:** feature (Track A — parser / symbol)
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** low (class methods work; only the per-class storage is missing)

## Gap

A `class var` (storage shared by all instances / accessed via the class) is not
recognized:

```pascal
type tc = class class var cnt: integer; end;
begin tc.cnt := 7; writeln(tc.cnt); end.
{ fpc: 7    pxx: error: class method not found: cnt }
```

`class function` / `class procedure` already work; only `class var` is missing
(the resolver looks for a method named `cnt`).

## Expected

`class var Name: T` declares one storage slot per class, addressable as
`TClass.Name` and from instances (FPC semantics).

## Repro

`type tc = class class var cnt: integer; end; tc.cnt := 7;`
