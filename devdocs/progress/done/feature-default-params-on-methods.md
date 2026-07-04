# Default parameter values on class/interface methods (works on free routines)

- **Type:** feature (parser — method declarations, Track A)
- **Status:** done
- **Owner:** —
- **Opened:** 2026-07-04 (bisecting the fgl wall; see [[fpc-lcl-compile-probe]])

## Problem

Default parameter values work on **free** routines but not on **methods**:

```pascal
function F(a: Integer; b: Integer = 10): Integer;          { OK }

type TFoo = class
  procedure M(n: Integer = 5);                             { pascal26: unexpected token }
  constructor Create(AItemSize: Integer = sizeof(Pointer));{ unexpected token }
end;
```

Any `= <default>` in a class/interface method parameter list errors — it is not
sizeof-specific (even `= 10` fails), so the method param parser simply has no
default-value clause. `fgl.pp`'s `TFPSList.Create(AItemSize: Integer =
sizeof(Pointer))` hits this (one of several fgl walls; see the probe doc).

## Root cause

The free-routine param parser (`ParseSubroutine`, ~parser.inc:13893) handles the
default:

```pascal
if CurTok.Kind = tkEq then begin Next; defaultVal := ConstEval; hasDefault := True; end;
```

The method param parsers do not:
- class-method params (in `ParseTypeSection`'s class body) — the param loop that
  ends at `if not Eat(tkSemicolon) then mDoneArgs := True` (~parser.inc:12234).
- interface-method params — the analogous loop (~parser.inc:11974).

Both parse the param type then expect `;`/`)`, so `=` is unexpected. They also do
not populate `ProcParamDefaultVal`/`pdefault` for the registered method proc, so
even if parsed, a call omitting the arg would not substitute it.

## Fix (Track A, parser.inc)

Mirror `ParseSubroutine`'s default-value clause into the two method param loops:
after the param type, accept `= ConstEval`, set the per-param default flag/value,
and record them into `ProcParamDefaultVal` for the method's proc index (the call
site already substitutes defaults from there — see the `.Create (parameter … has
no default)` path at ~parser.inc:5613). Depends on / pairs with
[[feature-sizeof-const-intrinsic-in-const-eval]] so `= sizeof(Pointer)` folds.

## Acceptance

- `procedure M(n: Integer = 5)` and `constructor Create(n: Integer =
  sizeof(Pointer))` compile; a call omitting the arg uses the default; a call
  supplying it overrides.
- Self-host byte-identical; `make test` green; regression `.pas`.

## Resolution (2026-07-04)

DONE (commit 54b20c0e). Mirrored ParseSubroutine default clause into the class-method and interface-method param loops; defaults stored at class-decl registration (Self-shifted). All nine method-call arg-parse loops accept a shorter call and fill trailing defaults (FillDefaultArgs helper, mirroring the ctor arity fill); body impls that repeat params without defaults no longer clear them. Covers ctor sizeof(Pointer) default, virtual-through-base, class-static, interface dispatch, paren-less calls. Regression test/test_default_params_methods.pas (12/12) in test-core. Self-host byte-identical, make test green.
