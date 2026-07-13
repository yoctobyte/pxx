---
prio: 50
---

# Class properties (and properties backed by a `class var`)

- **Type:** feature (Pascal frontend)
- **Track:** P — Pascal frontend (shared `parser.inc`, so Track A file-lane)
- **Status:** backlog — opened 2026-07-13.

## What is missing
```pascal
TA = class
  class var FV: Integer;
  class property V: Integer read FV write FV;   { TA.V := 8 }
end;
```
Two separate holes, and the second is the real one:

1. **`class property` is silently SKIPPED.** The class-body member loop only recognises
   `property`; with the `class` prefix the declaration is consumed as nothing and the
   property never exists. (Consuming the prefix is a one-liner — but on its own it just
   moves the failure to (2).)

2. **A property accessor cannot be a `class var`.** The read/write resolution looks for an
   instance FIELD, then a METHOD. A class var is neither, so it fails with
   `setter method not found: FV` — even for a PLAIN `property V ... read FV`, with no
   `class` prefix at all. That is the actual blocker, and it is why (1) alone gets you
   nowhere.

## Shape
Accessor resolution must fall back to `FindClassVar(ci, name)` when the accessor is
neither an instance field nor a method, and lower the access to that backing global
(which is already an LVALUE, so read and write both fall out — see how `TFoo.classvar`
already resolves).

The catch is that this resolution is open-coded in **nine** places (grep
`setter method not found` / `getter method not found`): instance vs class access, read vs
write, indexed vs plain, with-scoped. Doing it in one place and calling it from nine is
the actual work — patching one or two sites is how you get a feature that works in some
syntactic positions and not others, which is worse than not having it.

Qualified `TFoo.V` then resolves through the backing class var — that part is a small
addition to the class-qualified path that already handles `TFoo.classvar` and `TFoo.Const`.

## Gate
`make test` + self-host byte-identical.

## Log
- 2026-07-13 — opened. Attempted, then reverted: the prefix and the qualified-access half
  are easy, but the accessor fallback touches nine open-coded sites and deserves to be done
  once, properly, rather than half-landed.
