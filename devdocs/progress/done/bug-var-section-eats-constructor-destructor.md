# `var` section before a constructor/destructor impl fails — ctor/dtor eaten as a var name

- **Type:** bug (parser — declaration parsing, Track A)
- **Status:** DONE 2026-07-04
- **Owner:** Track A
- **Opened:** 2026-07-04 (landmine found while writing the
  [[bug-tobject-destroy-not-virtual-override]] regression test)

## Symptom

A `var` section immediately followed by a `constructor`/`destructor` method
implementation at program (or unit) level fails:

```pascal
program p;
type TFoo = class destructor Destroy; override; end;
var g: Integer;
destructor TFoo.Destroy; begin g := 1; inherited Destroy; end;   { pascal26:4: error: unexpected token }
begin end.
```

A `procedure`/`function` method impl in the same position compiles fine, and a
ctor/dtor impl *before* the `var` section compiles fine — so it looked like an
odd ordering rule.

## Root cause

`constructor`/`destructor` are **soft identifiers** in this dialect (`tkIdent`
with SVal `'constructor'`/`'destructor'`), not dedicated tokens like
`tkProcedure`/`tkFunction`. `ParseVarSection`'s entry loop
(`while CurTok.Kind = tkIdent and not <section-word>`) stopped only at
`implementation`/`initialization`/`finalization`. So when a var section was
followed by `destructor TFoo.Destroy`, the loop read `destructor` as the next
variable name, then hit `TFoo` where it expected `:`/`,` → "unexpected token".
`procedure`/`function` are real tokens, so the `CurTok.Kind = tkIdent` guard
already stopped the loop for them — hence the asymmetry.

## Fix

Extend `ParseVarSection`'s stop-list to the full set of soft-identifier
declaration-introducers that may follow a var section, matching the top-level
decl loop: `constructor`, `destructor`, `generic`, `specialize`, `operator`,
`label` (added to the existing `implementation`/`initialization`/`finalization`).
Verified none of these are used as a variable name in `lib/**`, `compiler/**`, or
`test/**`. One-site change; front-end only.

## Verified

- `var g; destructor TFoo.Destroy; …` and the `constructor` form compile + run.
- Interleaved `var … / method impls / var … / begin` works (the ordering FPC
  allows; also lets a `destructor Destroy; override;` body reference a program
  global declared before it — the pattern the TObject-override regression test
  originally couldn't use).
- `label` section after a `var` section still works (goto/label unaffected).
- Self-host byte-identical; `make test` green. Regression
  `test/test_var_before_method_impl.pas` (`ctor=1 dtor=1`) wired into test-core.
