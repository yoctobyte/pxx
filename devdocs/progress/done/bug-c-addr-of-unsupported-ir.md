# C `&` of certain operands lowers to IR_UNSUPPORTED (codegen crash)

- **Type:** bug
- **Status:** done
- **Track:** A (shared IR / codegen) — surfaced by Track C lua import
- **Opened:** 2026-06-25
- **Closed:** 2026-06-27
- **Found-by:** lua core import (lmem.c, ldebug.c) after the `(*expr)(args)`
  indirect-call parse fix (e4a991a) let those files parse past the allocator.

## Symptom

Both lmem.c and ldebug.c now reach codegen and die with:

```
Unsupported linear node in IR codegen! Kind=10 node=N IRA=35 IRB=… IRC=-1
pascal26: error: Unsupported linear node in IR codegen
```

`Kind=10` is `IR_UNSUPPORTED`; its `IRA` field is the unhandled AST node's kind,
and **35 = AN_ADDR** (`&expr`). So an address-of expression reached codegen as
`IR_UNSUPPORTED` — either `IRLowerAddress` (ir.inc ~833) or the `IRLowerAST`
fallthrough (~4026) produced it for an `&` whose operand form is not modelled.
IRA=35 (AN_ADDR) suggests the operand being addressed is itself an AN_ADDR (an
`&(&…)` shape) or an AN_ADDR the lowering mis-routes — needs confirmation by
printing the operand's inner kind at the fallthrough.

**Confirmed (instrumented IRLowerAddress fallthrough):** the node handed to
`IRLowerAddress` has `nodeKind=35` (AN_ADDR) and its inner `ASTLeft` is
`kind=11` (AN_FIELD). So the shape is `IRLowerAddress(AN_ADDR(AN_FIELD …))` =
**address-of-(address-of-field)** — a spurious double `&`. Most likely the C
frontend emits `&field` (an AN_ADDR) for a field that is an ARRAY (which in C
already decays to its address), and an enclosing `&` / address context then
wraps it again. Same shape in lmem.c (innerTk=5) and ldebug.c (innerTk=1).

## Fix options

- **Frontend (preferred):** in the C `&` / array-decay path, don't wrap an
  already-address-valued operand (array field / array) in another AN_ADDR.
- **IR:** have `IRLowerAddress` collapse `AN_ADDR(x)` to `IRLowerAddress(x)` when
  x is an array lvalue (the address of an array equals the array's address).
  Guard tightly so it doesn't mask genuine `&(rvalue)` errors.

## Status

- 2026-06-25 (Track C, e4a991a-successor) — **PARTIALLY FIXED.** Took the IR
  route: `IRLowerAddress` now collapses one `AN_ADDR` level
  (`IRLowerAddress(AN_ADDR(x)) := IRLowerAddress(x)`), which is correct for the
  array-field-decay shape `&s->v` / `&s.v`. This unblocked **lmem.c (now parses
  clean)** and advanced ldebug.c; self-host byte-identical, make test green,
  fixture `test/caddr_array_field_b16.c` (=42).
- **REMAINING:** `&s->v[0]` — taking the address of an array ELEMENT through an
  arrow-field base (`AN_ADDR(AN_INDEX(AN_FIELD(AN_DEREF …)))`) still hits
  IRLowerAddress's fallthrough (the value-base `&s.v[0]` works). Separate
  IRLowerAddress case needed for AN_INDEX over an arrow-field array.
- 2026-06-27 audit — **DONE / no longer reproducible.** Solved as a side effect
  of later Lua C-frontend debugging work. Current `compiler/pascal26` compiles
  the old Lua standalone probes far enough to report only `main function not
  found`; no `IR_UNSUPPORTED`, `Unsupported linear node`, or `AN_ADDR` failure is
  emitted for `lmem.c` or `ldebug.c`. The full Lua gate also passes via
  `make test-lua`.

## Repro

Not yet reduced to a minimal case — surfaces only inside the full lua headers
(the allocator/debug paths). To reproduce:
`./compiler/pascal26 -Ilibrary_candidates/lua/src library_candidates/lua/src/lmem.c /tmp/o`
(after staging lua-5.4.7). The new readable `  near:` error context (cd30d0c)
plus an instrumented print of the AN_ADDR operand kind at the IRLowerAddress
fallthrough will pin the exact construct.

## Resolution

Closed by verification rather than a targeted patch: the old failure is no
longer observable on current HEAD after the subsequent Lua C-frontend fixes.
