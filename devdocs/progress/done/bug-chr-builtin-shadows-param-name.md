# Bug: `Chr` as parameter name treated as built-in function

- **Type:** bug
- **Track:** A
- **Status:** done
- **Owner:** Codex
- **Opened:** 2026-06-28
- **Found-by:** Synapse v83 compile probe (Track B)

## Symptom

Using `Chr` (or `chr`, case-insensitive) as a **parameter name** triggers:

```
pascal26:N: error: untyped parameter requires var, const, or out ()
```

## Minimal repro

```pascal
program p;
function Foo(Chr: char): integer;
begin Foo := 0; end;
begin end.
```

Fails. Renaming the parameter to anything else (e.g. `C`) compiles fine.

## Root cause

The built-in `Chr()` function is being recognized as a keyword/reserved token
during parameter-list parsing, so the parser does not accept it as a parameter
name identifier. Standard Pascal allows any identifier (including built-in
function names) to be shadowed by a parameter name.

## Impact

Blocks `synautil.pas` (and transitively `synaip`, `asn1util`, `synachar`) in
the Synapse compile probe — `CountOfChar(const Value: string; Chr: char)` hits
this on every unit that uses synautil.

## Fix

Parameter name parsing should accept any identifier token, including those that
happen to match built-in function names. Only actual reserved **keywords** (e.g.
`begin`, `end`, `if`, `then`) should be rejected as parameter names.

## Log

- 2026-06-29 - Claimed by Codex.
- 2026-06-29 - Fixed in `compiler/parser.inc`: declaration-name parsing now
  accepts predefined/intrinsic tokens such as `Chr`, `Ord`, and `Length` in
  parameter-name slots, and bare shadowing symbols win over intrinsic parsing in
  expression position. Added `test/test_builtin_name_params.pas`.
  Verification: `make test-core` passed.
