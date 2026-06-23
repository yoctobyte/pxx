# bug: overload resolution binds a string arg to an earlier integer-param overload

- **Type:** bug (Track A — overload resolution) — silent wrong-overload call
- **Status:** done
- **Found:** 2026-06-23, differential probe vs FPC
- **Closed:** 2026-06-23
- **Severity:** medium-high (calls the WRONG routine silently)

## Resolution (2026-06-23)

Front-end only (overload ranking), no codegen. Root cause: a single-char string
literal (`'x'`) types as `tyChar`, and `TypesCompatible(tyInteger, tyChar)` is
true (both ordinal), so in the general compatible phase the first-declared
`f(integer)` overload matched a char arg and won. (`'hello'` types as tyString,
not ordinal-compatible with integer, so it already resolved correctly — hence the
asymmetry.)

Fix: new ranking phase 1c in `MatchProcCall` (symtab.inc), after the exact
phases and before the general compatible phase: a `tyChar` argument matches a
`tyString`/`tyAnsiString` parameter (every other arg must be an exact type
match). So `f('x')` binds to `f(string)` regardless of declaration order, while a
genuine `f(char)` overload still wins via the earlier exact phase, and a sole
`f(integer)` keeps its existing char->integer behavior (phase 2 unchanged).

Verified `f(1),f('x'),f('hello')` = INT|STR|STR both declaration orders, and
`h(integer)/h(char)` picks the char overload — byte-identical to FPC. Gate:
`make test` (self-host byte-identical — resolution only) + FPC oracle. Closes
bug-overload-resolution-by-type.

## Symptom

With two same-arity overloads of different parameter type, a `string` argument
selects the `integer`-parameter overload when it is declared first, instead of
the matching `string` one:

```pascal
function f(a: integer): string; begin f := 'INT'; end;
function f(a: string):  string; begin f := 'STR'; end;
begin writeln(f(1), '|', f('x')); end.
{ fpc: INT|STR    pxx: INT|INT   <- f('x') wrongly calls f(integer) }
```

## What works / the asymmetry

- Overload by **arity** is correct: `f(a)` vs `f(a,b)` resolves by argument count.
- An **integer** argument resolves by type in either declaration order
  (`f(1)` → the integer overload even when declared second).
- A **string** argument resolves correctly only when the string overload is
  declared first:

```pascal
function f(a: string):  string; begin f := 'STR'; end;
function f(a: integer): string; begin f := 'INT'; end;
begin writeln(f(1), '|', f('x')); end.   { pxx: INT|STR  (correct here) }
```

- A *sole* integer overload correctly rejects a string arg:
  `function f(a:integer)...; f('hello')` → `no overload of f matches`.

So an earlier `integer`-param overload is wrongly treated as a viable match for a
`string` argument during ranking (first viable wins), even though that same
conversion is rejected when the integer overload stands alone.

## Expected

Overload resolution selects by argument type independent of declaration order: a
`string` argument must bind to the `string`-param overload (FPC: `INT|STR`).

## Repro

`tools/fpc_diff_probe.sh` (`overload-by-type`).
