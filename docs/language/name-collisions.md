---
title: Name collisions
order: 49
---

# Name collisions, and the `as` escape

A program that mixes languages *will* hit two declarations of one name. That is
not an edge case — it is the ordinary consequence of putting `uses './mymath.c'`
next to a Pascal `Cube`. Both languages have a cube function; both are right;
you need a way to say which one you mean.

The rule is short:

> **A bare name binds by the resolution rules. A qualified name asks for a
> specific scope.** Qualification is the escape from any hiding.

## A Pascal unit already has a scope name

Its own:

```pascal
program qual;
uses pu;                     { pu declares Cube, returning 222.0 }

function Cube(x: Double): Double;
begin Cube := 999.0; end;

begin
  WriteLn(Cube(3.0):0:1);      { 999.0 — the local declaration hides pu's }
  WriteLn(pu.Cube(3.0):0:1);   { 222.0 — qualified reaches pu's           }
end.
```

## A foreign file has to be *given* one, with `as`

A file named by path has no unit name to qualify with, so `as` supplies it:

```pascal
program cubes;
uses './mymath.c' as cmath;   { C: double cube(double x) }

function Cube(x: Double): Double;
begin Cube := 27.0; end;

begin
  WriteLn(Cube(3.0):0:1);         { 27.0   — the bare name is Pascal's }
  WriteLn(cmath.cube(3.0):0:1);   { 1027.0 — C's, asked for by name    }
end.
```

The alias is a real scope, not a rename: `cmath.cube` reaches into the C file's
own symbols. This works across languages in both directions — a Nil Python
program can do the same thing:

```python
import './mymath.c' as c
print(c.cube(3.0))

import 'sysutils.pas' as su      # a unit name, through the search chain
print(su.Trim('  hi  '))         # hi
```

## Which one does the bare name pick?

Today, ordinary scope hiding: the declaration in the nearest scope wins, and a
local declaration hides an imported one. In the example above the Pascal `Cube`
wins over the C `cube` — note that the bare call matches **case-insensitively**,
because Pascal is a case-insensitive language and the call site is Pascal.

The settled rule the compiler is moving toward is **own language first**: a
bare name in a Pascal file prefers Pascal's declaration, a bare name in a C file
prefers C's. In the cases that exist today, scope hiding already produces that
answer. See [name resolution](./name-resolution.md#current-status) for what is
rule and what is not yet enforced.

**The practical advice does not depend on which of those lands.** If two
languages in your program declare the same name and you care which one runs,
qualify it. A qualified name is unambiguous under every rule above, and it says
to the next reader what you meant.

## When the escape hatch does not clear the wall

Reaching a Pascal RTL unit from Nil Python works for many units and not yet for
all of them — `import 'classes.pas' as cl` currently fails inside `classes.pas`
itself, while Pascal's own `uses classes;` compiles the same file fine. If a
`import '<unit>.pas' as …` fails with an error pointing *into* the Pascal unit
rather than at your import line, that is this gap and not a mistake in your
program. Check the project's issue board before working around it.

## Next

- [Name resolution](./name-resolution.md)
- [Nil Python](../targets/nil-python.md)
