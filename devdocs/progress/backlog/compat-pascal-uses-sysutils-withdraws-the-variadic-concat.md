---
track: P
prio: 25
type: compat
blocked-by: []
summary: "The variadic `Concat` intrinsic is shadowed by `sysutils`'s two-argument `Concat`, so `uses sysutils` breaks `Concat('a','b','c')` — which compiles fine without it. The shadow rule is `procIdx < 0`, i.e. ANY user Concat disables the intrinsic outright. Loud, not silent."
status: backlog
---

# `uses sysutils` breaks three-argument `Concat`

- **Track P** (Pascal frontend: the `Concat` intrinsic's shadow rule), tag
  **compat-pascal**.
- Found 2026-08-20 by an FPC differential probe over the string RTL. The first
  reading of the finding — "pxx's Concat only takes two arguments" — was wrong,
  and the correction is the whole ticket.

## Repro

```pascal
program cc;
begin
  Writeln(Concat('a', 'b', 'c'));    { prints abc }
end.
```

```pascal
program cc2;
uses sysutils;
begin
  Writeln(Concat('a', 'b', 'c'));    { error: no matching overload }
end.                                 {   candidates: Concat(AnsiString, AnsiString) }
```

pxx **does** have the variadic intrinsic — `ParseFactorCore` folds
`Concat(s1, ..., sn)` into a chain of `+`. It is guarded by `procIdx < 0`
("a user `Concat` shadows it"), and `sysutils` declares a two-argument `Concat`,
so importing sysutils silently withdraws the intrinsic and leaves the pair.

## Why the shadow rule is too coarse

Shadowing a builtin with a user routine of the same name is right; withdrawing
it for argument counts the user routine cannot accept is not. FPC keeps the
intrinsic and `uses sysutils` changes nothing there.

## Sketch

Two ways, both small:

- **Frontend:** relax the guard from "no user Concat exists" to "no user Concat
  overload accepts this argument count" — the call's comma count is available
  from the token stream before the arguments are parsed, which is how the
  existing lookahead in this arm already works.
- **Library:** drop `Concat` from `lib/rtl/sysutils` entirely, since the
  intrinsic covers the two-argument case as well. That is a Track B edit and
  fixes the symptom without fixing the rule.

The frontend one is the honest fix: any other unit declaring a `Concat` hits the
same wall.
