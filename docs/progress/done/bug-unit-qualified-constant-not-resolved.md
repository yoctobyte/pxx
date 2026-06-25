# Unit-qualified constant reference `Unit.Const` is not resolved

- **Type:** bug (parser / name resolution)
- **Status:** urgent (Track A)
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** [[feature-synapse-compile-check]] — `ssfpc.inc` re-exports
  `FIONREAD = termio.FIONREAD;` (and FIONBIO/FIOASYNC).

## Symptom

Referencing a constant qualified by its unit name fails everywhere:

```pascal
const X = termio.FIONREAD;     { ConstEval error: SVal = termio }
...
x := termio.FIONREAD;          { error: undefined variable (termio) }
```

Qualified **types** (`sockets.TInetSockAddr`, `BaseUnix.ptimeval`) and qualified
**function calls** (`dynlibs.LoadLibrary`, `SysUtils.StrLCopy`) both resolve fine
— synafpc compiles using them. Only a qualified **constant** is not found: the
parser treats the unit name as an undefined identifier instead of looking up the
constant in that unit's scope.

## Impact

Blocks Synapse's `synsock`/`blcksock` (and the protocol units `httpsend`/
`ftpsend`/`smtpsend` that pull them): `ssfpc.inc` does
`FIONREAD = termio.FIONREAD;` to re-export ioctl constants, which is standard
FPC. Any `Unit.Const` reference is affected.

## Fix

In name resolution for a qualified `A.B` where `A` is a used unit, look up `B` as
a **constant** in that unit's interface (the same lookup that already finds types
and functions there), in both constant-expression and ordinary-expression
context.

## Done when

- `const X = termio.FIONREAD;` and `x := termio.FIONREAD;` both compile and yield
  the constant's value.
- `synsock` gets past the ssfpc const block (next gap: the netdb / sockets
  address-string surface, RTL — Track B).
- Regression test under `make test`; self-host fixedpoint byte-identical.

## Resolution (2026-06-25, v58)

The ordinary-expression path (`x := Unit.Const`) already resolved (via
`ConsumeUnitQualifier` + `FindSymInUnit` in `ParseFactor`). Only the **const-
expression** evaluator `ConstEvalFactor` was missing it: its `tkIdent` branch did
a bare `FindSym(CurTok.SVal)` and never recognised a `Unit.Const` qualifier, so
`const X = termio.FIONREAD;` failed with "not a constant" (it saw `termio`).

Fix (`parser.inc`, `ConstEvalFactor`): reuse `ConsumeUnitQualifier` (leaves the
parser on the member name, yields the unit index) and resolve via
`FindSymInUnit` when qualified, else `FindSym` as before. Same lookup that already
serves qualified types and function calls.

Regression: `test/test_qualified_units.pas` extended with a qualified const
(`qualified_a.SharedConst`) used in both a const expression and an ordinary
expression. Self-host byte-identical; pinned v58.
