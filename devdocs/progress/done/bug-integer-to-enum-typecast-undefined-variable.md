# `TEnum(intExpr)` ordinal→enum typecast fails: "undefined variable"

- **Type:** bug
- **Track:** A — `compiler/**` (parser/typecast resolution)
- **Status:** backlog
- **Opened:** 2026-07-02
- **Found while:** Track B probing language features `feature-demo-chess`
  needs (piece-color/kind stored as small ints, converted to an enum type).

## Repro

```pascal
program P;
type
  TColor = (cWhite, cBlack);
var
  c: TColor;
  i: Integer;
begin
  i := 1;
  c := TColor(i);           { <-- fails }
  writeln(Ord(c));
end.
```

```
pascal26:9: error: undefined variable (TColor)
```

The **reverse** direction works fine:

```pascal
c := cBlack;
i := Integer(c);             { ok, prints 1 }
```

So enum→ordinal typecasts resolve, but ordinal→enum typecasts (`TEnum(expr)`)
are parsed as if `TColor` were being looked up as a variable/value identifier
rather than recognized as a type name in typecast position — asymmetric
handling of the same construct.

## Why it matters

Chess-style code commonly derives an enum from an arithmetic index (e.g.
`pos.sideToMove := TColor(1 - Ord(us))`, or table-driven piece-kind lookups
cast back to the enum type). `examples/chess/chess.pas` itself avoids this
particular pattern (uses `Opp()` / direct enum literals instead), so it isn't
currently blocking the demo, but it's a basic, commonly-expected cast direction
that silently breaks with a confusing error (a Pascal programmer would
strongly expect `TEnum(ordinalExpr)` to be a completely ordinary cast, not
suspect "undefined variable" — the message is also misleading, since `TColor`
is a perfectly well-defined type).

## Suggested investigation

Likely a gap in wherever the compiler recognizes `<ident>(...)` as a typecast
vs a call/variable reference — probably only checks a small set of built-in
target types (Integer/Byte/etc.) and record/class types, missing user-defined
enum types in that dispatch.

## Acceptance

- The repro above compiles and prints `1`.
- A few more enum-typecast shapes stay/become green: casting a `var`, a
  constant expression, and a function-call result to an enum type.
- Existing enum tests (`feature-enum-explicit-values`) stay green.

## Log
- 2026-07-02 — Filed by Track B. Isolated to a 2-line minimal repro; confirmed
  the reverse direction (enum→ordinal cast) already works, so this is
  specifically the ordinal→enum direction. No code touched — test/repro only.
