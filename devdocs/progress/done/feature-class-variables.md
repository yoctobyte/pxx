# feature: class variables (`class var`)

- **Type:** feature (Track A — parser / symbol)
- **Status:** done
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

## Resolution (2026-06-23)

`class var x: T` in a class body now allocates ONE shared global slot per class
(not per instance), registered in a new ClassVar table (defs.inc: ClassVarCi/
NOff/NLen/Sym). Resolution:
- `TClass.x` (ParseLValueAST class-static path): when the name is not a class
  method, FindClassVar resolves it to the backing global (an lvalue → read+write).
- `obj.x` (instance field path): when the name is not an instance field,
  FindClassVar (walks the parent chain — inherited class vars) resolves it to the
  same global.

`tc.cnt := 7; tc.cnt := tc.cnt + 5; a.cnt` -> 7,12,12 (instance sees the shared
value) — byte-identical to FPC objfpc; class/record test suite green; self-host
byte-identical. Follow-up: a bare `cnt` reference inside a class method body
(implicit class-var resolution) is not yet wired — use `TClass.cnt` there.
Closes feature-class-variables.
