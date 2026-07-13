---
prio: 50
---

# Advanced records: constructors (and `class operator`)

- **Type:** feature (Pascal frontend)
- **Track:** P — Pascal frontend (shared `parser.inc`, so Track A file-lane)
- **Status:** backlog — opened 2026-07-13.
- **Follows:** [[feature-pascal-advanced-records]] (methods landed; these are the two
  deliberately-excluded slices).

## What is missing
```pascal
TPt = record
  X, Y: Longint;
  constructor Create(ax, ay: Longint);
  class operator + (const a, b: TPt): TPt;
end;
...
p := TPt.Create(3, 4);
```
FPC's own `rtl/inc/typshrdh.inc` uses BOTH on TPoint/TSize/TRect, so a full parse of it still
needs them.

## Attempted 2026-07-13 — and where it ran aground (read this first)
The DECLARATION side is easy: a record constructor registers exactly like a record method
(Self = the record, by reference); it fills a fresh receiver rather than returning anything.
That part worked.

The CALL side is the problem. `TPt.Create(3,4)` must materialise a hidden temp, pass it as
Self, and have the EXPRESSION's value be that temp. The obvious vehicle is `ASTLiftedVar` —
the call is emitted as a statement and the node yields a load of the lifted var, which is
exactly the shape wanted, and is what the interface path already does.

**It segfaults.** `ASTLiftedVar` lowers to `IR_LOAD_SYM` of the lifted var, which loads a
VALUE. A record is carried BY ADDRESS in this IR, so `p := TPt.Create(...)` then copies from
a garbage address. The interface path gets away with it because it tags the node `tyPointer`
and an interface really is a (fat) pointer.

So the lifted path needs to yield an ADDRESS (`IR_LEA`) when the lifted var is a record — or
record ctors need a different vehicle. That is the decision to make, and it touches a path
the interface code shares, which is why it was not done as a drive-by.

Note it must NOT be routed through the class `Create` path: that lowers to GetMem and would
heap-allocate a record, handing back a pointer where a value belongs.

## Also here: `class operator`
Separate and probably easier — `class operator + (const a, b: TPt): TPt` is a static function
with a fixed name mangling, hooked into the binary-op resolution. pxx already has operator
overloading for classes ([[project_operator_overloading_exists_syntax_limits]]); this is
wiring records into it.

## Gate
`make test` + self-host byte-identical.
