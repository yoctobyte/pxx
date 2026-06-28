# Bug: named-type cast in constant expression fails ConstEval

- **Type:** bug
- **Track:** A
- **Status:** backlog
- **Opened:** 2026-06-28
- **Found-by:** Synapse v83 compile probe — `ssfpc.inc` (Track B)

## Symptom

A typecast using a named type alias inside a `const` expression triggers:

```
ConstEval error at SrcLine N: SVal = <TypeName> Kind = 1 TokPos = ...
pascal26:N: error: not a constant ()
```

## Minimal repro

```pascal
program p;
type TSocket = longint;
const INVALID_SOCKET = TSocket(NOT(0));
begin end.
```

Fails. `INVALID_SOCKET = longint(NOT(0))` (using the base type directly) likely
works; the failure is specific to using a **named type alias** as the cast
operator in a const expression.

## Root cause

`ConstEval` does not handle the `TypeName(expr)` cast form when `TypeName` is a
user-defined type alias. It encounters the identifier token (`TSocket`, Kind=1)
and cannot resolve it as a constant-expression cast operator.

## Impact

Blocks `synsock.pas` (and transitively `blcksock`, `httpsend`, `smtpsend`,
`ftpsend`) in the Synapse compile probe — `ssfpc.inc` defines
`INVALID_SOCKET = TSocket(NOT(0))` which every socket unit requires.

## Fix

`ConstEval` should resolve `TypeName(expr)` where `TypeName` is a known type
alias, evaluating it as a reinterpret/truncation cast of the inner constant
expression to the target type.
