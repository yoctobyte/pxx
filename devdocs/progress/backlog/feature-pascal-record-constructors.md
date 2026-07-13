---
prio: 50
---

# Advanced records: constructors + `class operator` — DONE

- **Type:** feature (Pascal frontend)
- **Track:** P — Pascal frontend (shared `parser.inc`, so Track A file-lane)
- **Status:** done — constructors AND `class operator` landed 2026-07-13.
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


## Constructors LANDED 2026-07-13

The blocker recorded above turned out to be the whole thing, and the fix was one branch:

`ASTLiftedVar` lowered unconditionally to `IR_LOAD_SYM`, which loads a VALUE — but a record
is carried BY ADDRESS in this IR, so `p := TPt.Create(3,4)` copied from a garbage address and
segfaulted. The lifted path now emits an **`IR_LEA`** when the lifted var is a record, and a
`IR_LOAD_SYM` otherwise. The interface path is untouched: it tags its node `tyPointer`, and a
fat interface pointer really IS a value.

So `TRec.Create(...)` materialises a hidden temp, passes it as Self by reference (like any
record method), and the expression's value is that temp. It is checked BEFORE the class
`Create` path, which lowers to GetMem and would heap-allocate a record and hand back a
pointer where a value belongs.

Covered by b268: a ctor result assigned, used through a method, and carried out of a function
as its result.

**Known gap:** postfix chaining directly on a ctor result — `TPt.Create(7,8).Sum` — does not
parse. The call node is not run through the postfix tail. Minor, and separable.

### Gate
make test green, make bootstrap green (FPC seed), make lib-test green, self-host
byte-identical, `testmgr --tier full` 1215/1215 GREEN.

## `class operator` LANDED 2026-07-13 — and it was mostly already there

The discovery that made this small: **a plain top-level `operator + (const a, b: TPt): TPt`
on records ALREADY worked.** pxx keys an operator on its OPERAND TYPES, not on an owning
type. So FPC's advanced-record spelling needed no new machinery at all — only for the
existing machinery to accept it:

- `class operator + (...)` INSIDE the record is the SIGNATURE. It carries nothing the
  definition does not, so it is parsed and discarded.
- `class operator TPt.+ (...)` at top level is the DEFINITION. ParseOperatorDef now drops the
  `class` prefix and the `TRec.` qualifier and proceeds exactly as for a plain `operator`.
  Dispatched from the tkClass branch of the top-level decl loop, with the same
  pre-scan handling a plain operator gets (bug-unit-operator-def-silently-skipped).

Verified with `+` and `=` on a record that also has a constructor and methods.

### Known gap (filed, not bodged): operator operands that are CALL RESULTS
`TPt.Create(1,2) + TPt.Create(10,20)` fails with "no operator overload found for record
operands". The operands are record-valued CALL nodes, and operator dispatch only recognises
record operands it can see as variables/lvalues. Variables work
(`d := b + c`), which is what b268 pins. Split out as
[[bug-pascal-operator-on-record-call-result]].
