# Bug: `Chr` as parameter name treated as built-in function

- **Type:** bug
- **Track:** A
- **Status:** backlog
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
