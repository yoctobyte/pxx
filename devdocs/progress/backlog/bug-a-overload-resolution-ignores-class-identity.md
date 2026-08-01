---
summary: "Overload resolution never checks CLASS IDENTITY for a class-typed parameter — it takes the first candidate whose arity fits, so an unrelated class binds silently and the callee reads one class's fields as another's"
type: bug
track: A
prio: 80
---

# Overload resolution binds an unrelated class to a class-typed parameter

- **Type:** bug (Track A, shared overload resolution — SILENT WRONG DISPATCH,
  and a crash wherever the two layouts differ) — **Track A**
- **Opened:** 2026-08-01, found while fixing
  [[bug-nilpy-dict-from-pairs-and-bytes-decode-segfault]]. That ticket's own
  "it is a TYPECAST" diagnosis is wrong; this is the actual cause, and it is far
  bigger than `dict()`.

## Minimal repro — plain PASCAL, no NilPy involved

```pascal
program ov;
type
  TA = class
    x: Integer;
  end;
  TB = class
    y, z: Integer;
  end;
function pick(a: TA): Integer; overload;
begin pick := 1; end;
function pick(b: TB): Integer; overload;
begin pick := 2; end;
var b: TB;
begin
  b := TB.Create;
  WriteLn(pick(b));    { CPython-free, unambiguous: must print 2 }
end.
```

**Prints `1`.** `TA` and `TB` are unrelated — no inheritance, different layouts.
Resolution took the first candidate whose ARITY fits and never compared the
argument's class to the parameter's.

## Why it matters

- **Silent** in the benign case: you get the wrong function, no diagnostic.
- **A segfault** whenever the two classes' layouts differ and the callee touches
  a field or method — the callee is reading one object's memory through another
  class's shape. That is how it surfaced: `dict([("a", 1)])` bound its TPyList
  to `function dict(d: TPyDict)`, whose body calls `d.keylist`.
- **Blast radius is every overload set with class-typed parameters.** `pylib`
  alone has many (`dict`, `list`, `reversed`, `bytes`, the `TPyDict.update`
  pair). Any of them can be handed the wrong class by a caller and bind happily.
- Ordering becomes load-bearing in a way nobody can see: whichever overload is
  DECLARED FIRST wins for every class argument. Reordering to fix one call
  breaks another (measured — see the sibling ticket).

## Where to look

`compiler/parser.inc`, the overload selection around lines ~3253–3415
(`FindUMethArity` / the candidate scan and the "type-match phases"). The comment
on `ProcArityMatches` (`symtab.inc:4689`) says the type-match phases "only check
the supplied args[0..nArgs-1]" — the question is what that check does for a
`tyClass` parameter, and the measured answer is: nothing that distinguishes one
class from another.

## Care required — do NOT simply require exact class equality

The fix must keep the cases that legitimately bind:

- a **descendant** passed to an ancestor-typed parameter (`IsSubclassOf` already
  exists and is used elsewhere in the resolver),
- `nil`,
- a parameter typed `TObject`, which must keep accepting anything,
- interface-typed parameters,
- the pylib paths that pass a class through a `Variant` parameter.

A too-strict rule will reject working code across every track, so this wants the
full gate and probably a staged landing (warn first, then reject) rather than a
single flip.

## Gate

The repro above prints `2`; `make test` + self-host byte-identical + the
frontends' suites green. Add the repro as a regression test. Then re-check
[[bug-nilpy-dict-from-pairs-and-bytes-decode-segfault]], which should start
working with no further change — its `dict(l: TPyList)` overload is already in
`pylib.pas`, deliberately left unselected and waiting for this fix.
