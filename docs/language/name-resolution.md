---
title: Name resolution
order: 48
---

# Name resolution

PXX compiles several languages — Pascal, C, Nil Python — through one shared
intermediate representation, and a program may mix them in a single build. That
raises a question a single-language compiler never has to answer: **if two
declarations in two different languages share a name, which one does a bare call
bind to?**

This page answers it for the programmer. The short version:

1. Your own language wins.
2. A cross-language name has to agree on **case** to match at all.
3. A declaration in your own scope shadows an imported one — and that is
   allowed, not a wart.
4. Each frontend follows its own reference implementation, so the same-looking
   construct can legitimately give different answers in a `.pas` and a `.npy`.

## Two different questions

"Own language first" is the slogan for both halves of the problem, but they are
separate machinery and it is worth keeping them apart:

| | question | answer |
| --- | --- | --- |
| **Module** resolution | which *file* does this import name load? | each frontend searches its own extension only |
| **Symbol** resolution | which *declaration* does this name bind to? | own language first, then scope hiding, then overload matching |

## Module resolution — which file

A bare import name means **this language's own module**. `uses math` in Pascal
looks for `math.pas`; `#include <math.h>` in C searches the C include path; a
Nil Python `import tkhtmlview` looks for `tkhtmlview.py` or `.npy` and **only**
those. No frontend implicitly searches another language's files, and that is
deliberate: importing another language is something you say out loud.

Nil Python enforces this with a diagnostic rather than a silent fallback. A
name that happens to match a Pascal RTL unit is refused, and the message names
the file it found and the spelling that reaches it:

```
error: import: classes is the Pascal unit …/lib/rtl/classes.pas, not a Python
module — a bare NilPy import resolves to Python (.py/.npy) only. To reach the
Pascal unit, name it with its extension: import 'classes.pas' as classes
```

That refusal is the point. Before it, such an import loaded the Pascal unit and
failed somewhere inside a file the program never mentioned.

### To reach another language, name the file

A quoted string with a foreign extension routes that file through the other
frontend. What the string may look like differs by language, because each
frontend keeps its own convention rather than a symmetry imposed on all three:

| you are writing | spelling | what it does |
| --- | --- | --- |
| Pascal | `uses './mymath.c';` | compiles `mymath.c` through the C frontend; its functions are callable unqualified |
| Pascal | `uses './mymath.c' as cmath;` | the same, and gives the file a **scope name** — see [name collisions](./name-collisions.md) |
| Pascal | `uses './mymod.pas';` | an ordinary Pascal unit named by path rather than by unit name |
| C | `#include "./lib2.c"` | ordinary C inclusion |
| Nil Python | `import './mymod.pas' as m` | a **path** (it contains a `/`), resolved against the importing file's directory |
| Nil Python | `import 'sysutils.pas' as su` | a unit **name** carrying an extension, resolved through the normal search chain — this is how a `.npy` reaches `lib/rtl` |

```pascal
program cubes;
uses './mymath.c';   { C's cube, deliberately }
begin
  WriteLn(cube(3.0):0:1);
end.
```

The C functions the file defines become callable from Pascal.

Two asymmetries worth knowing rather than discovering:

- **The slash is the difference in Nil Python.** With a `/` the string is an
  authoritative path; without one it is a unit name and goes through the search
  chain. Both are unambiguous because both are string literals.
- **Pascal has only the path form.** `uses 'sysutils.pas' as su;` — a quoted
  name with no slash — is *not* accepted from Pascal (`uses: unit source not
  found`), because Pascal already reaches its own RTL by bare unit name and
  needs no second route to it.
- **The dotted spelling is not built.** `import mymod.pas as m` fails, and
  deliberately so: `a.b` is Python's package-submodule syntax, and making an
  extension distinguishable from a submodule would need a whitelist that a real
  package with a submodule named `c` or `pas` would defeat. The quoted form is
  the supported one.

### What cross-import is for

Cross-import exists so a program can reach **the other language's real
libraries** — `import sqlite.c` from Nil Python to compile SQLite in
statically, or pulling a C numerics routine into a Pascal program.

It is not a route for a `.npy` to borrow Pascal's RTL. Each frontend has its own
runtime library, and each keeps its own semantics; see
[Which reference implementation applies](#which-reference-implementation-applies)
below.

## Symbol resolution — which declaration

### Case must agree across languages

A cross-language match is **case-sensitive**, even though Pascal itself is not.
Carrying the earlier example forward:

```pascal
program t2;
uses './mymath.c';
begin
  WriteLn(Cube(3.0):0:1);   { error: undefined variable (Cube) }
end.
```

`cube` matches C's `cube`; `Cube` does not. Within Pascal, `Cube` and `cube`
remain the same name as always — the case rule applies only when the candidate
comes from another language.

This one rule closes most of the collision class on its own, because the two
spelling conventions do not overlap: Pascal library names are capitalised
(`Exp`, `Round`, `Sin`) and C library names are lowercase (`exp`, `round`,
`sin`).

### Your own language wins

Where a name genuinely exists in both languages, the call site's own language
takes precedence. It outranks import order.

A C call to `exp` binds C's `exp`; a Pascal call to `Exp` binds Pascal's. **They
are different functions and they are allowed to be** — the two implementations
have different accuracy targets and different edge cases, and neither is a
degraded copy of the other. `Round(2.5)` is `2` in Pascal and `3` in C, and both
are correct for their language.

Where a real ambiguity survives, the compiler's obligation is to **warn and name
what it picked**, not to guess quietly. Qualification (below) is the escape.

If you deliberately pull both `math.pas` and `math.c` into scope and then write
an ambiguous bare call, you own that outcome. The compiler will tell you what it
did; it will not pretend the question does not exist.

### Shadowing is allowed — and preferred

A declaration hides a same-named one from an earlier or outer scope, unless it
is marked `overload`. This is the ordinary Object Pascal rule, and it applies to
imported cross-language names too:

```pascal
program shadow;
uses './mymath.c';

function cube(x: Double): Double;
begin
  cube := 999.0;
end;

begin
  WriteLn(cube(3.0):0:1);   { 999.0 — the local one }
end.
```

For a `uses a, b` clause, the **last** unit named wins, matching FPC.

Shadowing is not something to apologise for. The reference implementations allow
it, so PXX does, and the shadowed routine stays reachable under a qualified
name.

### Qualification reaches past the shadow

A qualified reference has already named its scope, so scope hiding does not
apply to it:

```pascal
program qual2;
uses pu;                     { pu declares Cube, returning 222.0 }

function Cube(x: Double): Double;
begin
  Cube := 999.0;
end;

begin
  WriteLn(Cube(3.0):0:1);    { 999.0 — the local one shadows }
  WriteLn(pu.Cube(3.0):0:1); { 222.0 — qualified, reaches pu's }
end.
```

Same rule for the built-ins: `System.Random(i + 1)` reaches the builtin even
when a used unit declares its own `Random`.

## Which reference implementation applies

**Each frontend follows its own language's reference implementation:** CPython
for `.npy`, FPC for `.pas`, and ISO C / the C library for `.c`. Deviations from
that default live behind explicit `--strict-*` flags.

This is the rule that explains most surprises, so it is worth seeing measured.
The same rounding call, in three languages, on the same compiler:

```pascal
{ r.pas }
program r;
begin
  WriteLn(Round(2.5));   { 2 }
  WriteLn(Round(3.5));   { 4 }
end.
```

```python
# r.npy
print(round(2.5))   # 2
print(round(3.5))   # 4
```

```c
/* r.c */
#include <stdio.h>
#include <math.h>
int main(void) {
  printf("%.0f\n%.0f\n", round(2.5), round(3.5));  /* 3, then 4 */
  return 0;
}
```

Pascal and Nil Python round half to even, because FPC and CPython do. C rounds
half away from zero, because C does. Nothing here is a bug in the other two.

The practical consequence for mixed-language programs: **when you cross a
language boundary, you cross a semantics boundary too.** The function you
imported behaves the way its own language says it should, not the way the
calling language would have.

## Current status

Two parts of the above are settled rules that the compiler does not fully
enforce yet. They are documented here because they are the rules the language
has, but do not write code that depends on them landing:

- **Own-language-first is not yet implemented as an explicit precedence.** Today
  the case rule and ordinary scope hiding produce the right answer in the known
  cases, and a bare call that is ambiguous across languages resolves without a
  warning rather than with one.
- **Scope hiding covers routines, not types and classes.** Two units exporting
  the same *class* name still resolve first-match rather than last-named.
- **`from '<file>' import <name>` is not built.** The `as` form is how a
  foreign file is imported; `from 'sysutils.pas' import Trim` is refused with
  *expected a module name after from*.

Module scoping — specifically whether a `uses` clause is transitive — is not
documented here yet, because it is still being settled in the compiler.

## Next

- [Name collisions](./name-collisions.md)
- [PXX dialect](./dialect.md)
- [FPC compatibility](./fpc-compatibility.md)
