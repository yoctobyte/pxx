---
slug: bug-a-a-source-type-alias-loses-to-a-used-units-function-in-a-cast
track: A
prio: 50
status: done
commit: d699b2d23
---

# `type PI = ^Integer` — and then `PI(p)^` is a call to math's `Pi`

```pascal
type PI = ^Integer;
var i: Integer; q: PI; pp: Pointer;
begin
  i := 42; q := @i; pp := q;
  WriteLn(PI(pp)^);
end.
```

```
error: no overload of PI matches these arguments
  argument types: (Pointer)
  candidates:
    PI()
```

An error about *arguments* for a construct that does not take any. It sends the
reader to look at the cast — at `pp`, at the `^`, at whether pointer casts work
at all — when the mistake is in the *name*: `PI` bound to the paramless
function `Pi`, which the math unit exports and which the pre-scan pulls in for
any program containing that token.

The name is not a coincidence. `PI` is the conventional Pascal spelling of
`^Integer`, and the RTL's π is the one routine whose name collides with it.

## Innermost wins — the arm nobody wrote

Name resolution here already applies "the nearest declaration wins" in two
places at the same site: a program's own ROUTINE beats a used unit's
(`bug-p-program-function-does-not-shadow-used-unit`), and a NilPy program's own
CLASS beats a pylib routine
(`bug-nilpy-user-class-named-like-a-pylib-builtin-is-shadowed`). **Types were
the case nobody added**, so the only names that could ever collide were the few
an RTL unit exports as a function — which is why one name accounts for
essentially every occurrence, and why it went unnoticed.

The fix is the third arm, next to the other two:

```pascal
if (not NilPyUserCode) and (qUnit < 0) and (procIdx >= 0) and (idx < 0) and
   (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
begin
  aliasIdx := FindTypeAlias(name);
  if (aliasIdx >= 0) and (AliasUnitIdx[aliasIdx] = CurrentUnitIdx) and
     (ProcUnitIdx[procIdx] <> CurrentUnitIdx) then
    procIdx := -1;
end;
```

Narrow on purpose:

- **only in front of `(`** — the one position where a type name means a CAST;
- **only when the alias is declared in the unit being compiled and the routine
  is not** — so a type from unit A never steals a call to a function from unit
  B, and a compiler-registered builtin alias is not involved at all;
- a type and a routine of one name in ONE scope is illegal, so this can never
  choose between two local declarations.

## A deliberate divergence, recorded

FPC's shadowing is **total**: after `type PI = ^Integer`, the name `Pi` is the
type everywhere, and `d := Pi` is an error (`Incompatible types: got "PI"
expected "Double"`). PXX now takes the cast in front of `(` and still reaches
the function elsewhere, so it accepts *both* — every FPC-accepted program still
compiles and means the same thing, and some FPC-rejected ones compile too.

That is the dialect's standing posture (CLAUDE.md: "PXX's own dialect stays
deliberately lax by default; FPC-parity strictness lives behind per-feature
strict flags"), and the laxness is in the safe direction here. Row 3 of the test
pins it and says so — it is the one row with no FPC twin.

## Verification

`test/test_source_type_beats_unit_function.pas`:

```
PI(pp)^ = 42        the failing cast
Fmt(pp)^ = 'hi'     a second alias whose name collides with NOTHING — the control
d := Pi             the routine is still reachable by its own name (no FPC twin)
PI(pp) = nil        the cast still wins after the routine has been used
total ok 4 / 4
```

Found by the type-conversion/cast differential family.

Gate: `make compiler/pascal26` (fixedpoint, converged after 1 round) +
`tools/gate.sh quick` GREEN.
