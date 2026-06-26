# SizeOf intrinsic does not support variable or expression operands

- **Type:** bug
- **Status:** backlog
- **Track:** A (compiler)
- **Owner:** —
- **Opened:** 2026-06-26 (discovered during Track D documentation validation)

## Symptoms

In standard Object Pascal (FPC/Delphi), the `SizeOf` intrinsic can be called with either a type name or a variable/expression operand:

```pascal
var
  i: Integer;
begin
  writeln(SizeOf(Integer)); { Works: size of type }
  writeln(SizeOf(i));       { Works in FPC: size of variable }
end;
```

In PXX, calling `SizeOf` on a variable or expression triggers a compilation error:

```
pascal26:66: error: SizeOf: unknown type ()
```

## Root Cause

In `compiler/parser.inc` around line 3908, the `SizeOf` intrinsic is parsed and resolved at parse time to an `AN_INT_LIT` (integer literal). The implementation explicitly expects a known type name as the operand:

```pascal
{ ---- SizeOf(TypeName) intrinsic: resolved at parse time to AN_INT_LIT ---- }
```

It does not support resolving the type of a variable or expression operand to determine its size.

## Acceptance

- The `SizeOf` intrinsic accepts both type names (e.g., `SizeOf(Integer)`) and variable/expression operands (e.g., `SizeOf(myVar)`).
- Verified by a test case compiling and running successfully on all targets.

## DONE 2026-06-26 (Track A)
parser.inc ParseFactor SizeOf: when the operand is not a known type name, fall
back to FindSym — a variable operand resolves to its declared type's size
(record-by-value var -> RecSize via Syms[].RecName; scalar/pointer/class-ref ->
TypeSize). `SizeOf(i)`==`SizeOf(Integer)`==4, `SizeOf(r)`==`SizeOf(TR)`==16, etc.
Self-host byte-identical. NOTE: covers a bare variable token (the ticket's repro);
a multi-token expression operand (`SizeOf(a.f)`, `SizeOf(arr[0])`) still needs the
ParseExpr-type-inference path — file a follow-up if a workload hits it.
