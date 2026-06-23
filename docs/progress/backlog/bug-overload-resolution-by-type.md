# bug: overload resolution binds a string arg to an earlier integer-param overload

- **Type:** bug (Track A — overload resolution) — silent wrong-overload call
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** medium-high (calls the WRONG routine silently)

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
