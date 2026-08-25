---
track: P
prio: 45
type: feature
blocked-by: []
summary: "A record typed constant whose FIELD is an array of records is refused (`not a constant`): `CR: TR = (a: ((x:1;y:2),(x:3;y:4)))`. The kind-7 array-valued-field path handles scalar elements only; FPC compiles it."
status: backlog
---

# A record constant with an array-of-RECORD field does not parse

- **Track P** (Pascal frontend: `ParseConstSection`'s record-constant arm).
- Found 2026-08-20 by an FPC differential probe (the probe that found
  [[bug-p-record-field-array-with-a-non-zero-low-bound-writes-out-of-bounds]]).
  Loud, not silent — it is a compile error, which is why this is a feature
  ticket and not a bug.

## Repro

```pascal
type
  TSub = record x, y: Integer; end;
  TR = record g0: Integer; a: array[1..3] of TSub; g1: Integer; end;
const
  CR: TR = (g0: 7; a: ((x:1;y:2),(x:3;y:4),(x:5;y:6)); g1: 8);
```

```
pascal26:22: error: not a constant
  near:   a    >>> x
```

FPC 3.2.2 compiles and runs it.

## Where it stops

The record-constant arm already has an **array-valued field** path — it emits
one `sym.field[k] := v` init per element (PendingInitKind 7) — and it reads each
element through `ParseInitValTk(fTk)`, i.e. a SCALAR. A `(x:1;y:2)` element is a
record constant, so the scalar reader meets `x` and reports "not a constant".

Note the neighbouring case that DOES work: a top-level `const t: array[1..N] of
TRec = ((name:'AND'; c:1), ...)` — the array-of-record-with-named-fields form
Pascal Script's keyword table needs. So the two halves of the same concept are
split across two arms, and only the nested one is missing.

## Sketch

The kind-7 emitter builds `sym.field[k]`, and the record-element path builds
`sym[k].field`; what this needs is `sym.field[k].subfield`, i.e. one more
component in the same target chain. `PendingInitFOff` already carries one field
span and `PendingInitValAux` the element index, so the shape is there — it needs
a second field span (or a small target-path encoding) rather than a new
mechanism.

## Gate

The repro compiles and its values match FPC; a test under `test/` pins the
nested form alongside the two that already work.
