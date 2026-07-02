# Implicit-Self method call loses to a same-name plain proc from a used unit

- **Type:** bug (name resolution — FPC scoping) — Track A
- **Status:** backlog
- **Opened:** 2026-07-02, exposed by the Move/FillChar builtin sweep;
  **verified pre-existing at v144** (rebuilt that compiler from git: same
  failure, so unrelated to the v145+ Move work).

## Symptom

Inside a method, a bare call to another method of the same class resolves to
a same-name PLAIN PROC from a `uses`d unit instead of the class's own method:

`examples/adventure/engine.pas:1038` — `Move(d)` inside a TGame method, with
`TGame.Move(d: TDirection)` declared, but `uses sysutils` (which still has
the 3-arg `Move`) → `no overload of Move matches these arguments` /
`Mismatch in MatchProcCall: name = Move, nArgs = 1; candidate paramCount=3`.
The class's own 1-arg method is never considered. FPC: innermost scope (the
class) wins — this compiles.

Minimal repro compiles fine when NO plain proc named Move exists — the bug
needs the name collision. Currently breaks the adventure demo (dashboard
FAIL, pre-existing).

## Likely fix

In the statement/factor ident call classification, check
`FindUMeth(CurSelfClass, name)` BEFORE falling through to the plain-proc
MatchProcCall — or make MatchProcCall failure fall back to the method path
instead of erroring. Same family as the unqualified Read/Write→member fix
(done 2026-06-25) and the Move/FillChar soft-alias guard (v149), both of
which already consult FindUMeth — the generic call path is what's missing it.

## Acceptance

adventure.pas compiles + demo green; minimal repro (method Move + uses unit
with proc Move) FPC-parity; no change to plain overload resolution
otherwise; self-host byte-identical.
