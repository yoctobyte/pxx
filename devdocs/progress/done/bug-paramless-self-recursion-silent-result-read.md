# Paramless self-recursion reads own Result silently — no diagnostic

- **Type:** bug / dev-footgun (compiler language semantics)
- **Status:** done
- **Track:** A (compiler core / parser-semantics) — raised by Track C (C frontend).
- **Opened:** 2026-06-25

## Symptom

Inside a parameterless function, writing the function's OWN name without `()` is
parsed as a read of its result variable (TP/`fpc`-mode bare-funcname rule), NOT a
recursive call. Silent: no warning, no error. A recursive descent parser written
the "obvious" way miscompiles.

```pascal
function ParseCUnary: Integer;
begin
  ...
  operand := ParseCUnary;   { reads ParseCUnary's OWN Result (0), NOT a call }
  ...
end;
```

`operand` becomes the uninitialised Result (0 / stale), the recursion never
happens, and downstream logic builds a corrupt AST. In Track C this produced an
AST cycle (`AN_NEG.left -> the enclosing AN_BLOCK`) that only surfaced as an
IRLowerAST stack overflow at a DIFFERENT site, ~an hour to trace. Fix is trivial
once known — `ParseCUnary()` with empty parens forces the call — but nothing
points at it.

## Why it matters

- It is layout-/context-insensitive and self-host-invisible: the seeded compiler
  and the self-host both apply the same rule, so `make bootstrap` stays
  byte-identical while the user program is silently wrong.
- It bites every recursive-descent author (the C frontend has many paramless
  recursive helpers: ParseCUnary, ParseCExpr, …). The same family already burned
  earlier work (see memory: "F() required to recurse", "bare funcname read =
  result var ALL param counts").

## Proposed fix (Track A)

Emit a **warning** (ideally) when a parameterless routine's own name appears bare
in expression/assignment position inside its own body — "did you mean `Name()`
(recursive call) or is this the function result? use `Result`/`Name()` to
disambiguate." Even a note would have saved the hour. A stricter option: in
`{$mode objfpc}`-like strictness, treat bare own-name as the result var only as
an assignment TARGET, and as a call in value position when followed by `(`,
erroring on the ambiguous bare value read.

Non-goal: changing the default bare-funcname-is-Result semantics (self-host
depends on it). Just surface the ambiguity.

## Workaround (in effect)

Always call paramless routines (incl. self-recursion) as `Name()`. Documented in
the Track C resume notes / landmines.

## Resolution

The compiler already had the intended opt-in diagnostic behind
`--warn-self-result`; this ticket was stale. Added regression coverage:

- normal compile preserves existing FPC-compatible bare-name-as-Result behavior;
- `--warn-self-result` emits the ambiguity warning;
- `--warn-self-result -Werror` promotes the warning to an error.

Verified:

```
./compiler/pascal26 test/test_warn_self_result.pas /tmp/test_warn_self_result26
./compiler/pascal26 --warn-self-result test/test_warn_self_result.pas /tmp/test_warn_self_result_warn26
./compiler/pascal26 --warn-self-result -Werror test/test_warn_self_result.pas /tmp/test_warn_self_result_werror26
```

## Log

- 2026-06-29 — resolved; commit in this changeset.
