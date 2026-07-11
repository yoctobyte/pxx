---
prio: 30
---

# schema types (ISO 10206 value-parameterized types) — experimental

- **Type:** feature (Pascal frontend) — Track P, **X-tagged** (experimental,
  never ranks; user-requested filing 2026-07-11)
- **Status:** experimental — parked until someone wants it
- **Owner:** —

## What

ISO 10206 Extended Pascal schema types: types parameterized by VALUES
(discriminants), not by types — Ada-style:

```pascal
type
  matrix(m, n: integer) = array[1..m, 1..n] of real;
var
  a: matrix(3, 4);                 { concrete instance }
procedure invert(var x: matrix);   { formal accepts any m x n; bounds
                                     queryable at runtime }
```

Even ISO `string(80)` is officially a schema (capacity = discriminant).

## Why (user, 2026-07-11)

"They have some elegance, and on first sight don't seem to conflict any other
syntax." Valid concept — but note pxx already covers the dominant use case
(runtime-dimensioned arrays) with dynamic arrays + open array parameters, so
this is elegance, not necessity. Hence experimental.

## Scope sketch

- Parser: `type name(param: type; ...) = <type-expr using params>` — new
  syntax after the type name; instantiation `name(args)` in type position.
- Semantics: discriminants stored with the instance (hidden header or
  compile-time-only for static instances); formal-schema parameters need
  runtime bounds access (like open arrays' hidden length, generalized).
- Cheap first rung: compile-time-only schemas (every instantiation has
  constant discriminants) — pure frontend expansion to a concrete type,
  zero IR change. Runtime formal-schema params are the expensive half; that
  part IS shared-core work → would need a Track A ticket if promoted.

## Gate

Experimental rules: Pascal tests green + self-host byte-identical; feature
behind a switch if it ever destabilizes (FPC-faithful default per user rule —
FPC itself does NOT support schemas outside partial ISO modes).
