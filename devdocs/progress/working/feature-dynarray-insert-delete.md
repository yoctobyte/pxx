# `Insert` / `Delete` intrinsics for dynamic arrays

- **Type:** feature (compiler intrinsic) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Found by:** feature-dynarray-torture-test.
- **Relation:** the dynarray siblings of the string `Insert`/`Delete` (done) and
  [[feature-copy-intrinsic]] (the same generic-over-element-type shape).

## Symptom

```pascal
var a: array of Integer;
begin SetLength(a,4); ...; Delete(a, 1, 2); end.   { -> error }
begin ...; Insert(99, a, 1); end.                  { -> error }
```
→ `Delete: string argument expected (dynamic-array Delete not yet supported)` /
`Insert: string destination expected (dynamic-array Insert not yet supported)`.
String `Insert`/`Delete` work; the dynamic-array forms are explicitly rejected.

## Scope

- `Delete(arr, index, count)` — remove `count` elements at `index`, shift down,
  shrink. Element-type aware (managed elements released).
- `Insert(value, arr, index)` — grow by 1, shift up, store `value` at `index`.
  (FPC also has `Insert(srcArr, arr, index)` to splice an array — phase 2.)

## Fix sketch

Generic over element type (like Copy) — needs a per-element-size lowering or a
runtime helper taking element size + a managed-field descriptor. The string
versions in builtin.pas are the template; the dynarray versions must handle
arbitrary element size + managed-element release on Delete.

## Design investigation (2026-07-02, Track A) — parked, not implemented

Picked up, scoped, then deliberately parked rather than landed overnight — this
crossed from "small" into "has a real, un-reviewed design decision" territory,
which the session's own operating rule says to park rather than commit solo.
Recording the investigation so the next pass (or a review with the user) starts
from a concrete plan instead of from scratch.

**`AN_DYN_COPY` (ir.inc:2298) is the template**, and it is generic-over-T the
same way this needs to be: element size/type read off the source symbol, a
fresh dyn-array temp `SetLength`'d then filled via `PXXMemCopy`. Two things
`Copy` gets to skip that `Delete`/`Insert` cannot:

1. **Copy never mutates its source; Delete/Insert must.** `Copy` only ever
   *reads* the source array and returns a brand-new dyn-array value — the
   result assignment / scope-exit release path already used everywhere else
   handles the new value's lifetime. `Delete`/`Insert` are `var`-semantics on
   the array itself: the array's own handle slot must be replaced (old block
   released, new block's refcount/ARC state correct), which is the same
   "become unique / replace the handle" shape `PXXDynSetLen`'s growth path
   already does internally — but I have not traced whether that exact
   handle-replacement logic is reusable as a callable helper for an existing
   symbol's slot from *this* call site, or needs re-deriving. This is the part
   that most wants review before landing, since a mistake here is a refcount/
   double-free bug, not a wrong-answer bug.

2. **`Insert`'s shift is in the unsafe `memmove` direction; `Delete`'s is not.**
   `Delete(arr, index, count)` shifts the tail *down* (dest < src) — safe for
   a plain ascending byte copy, so `PXXMemCopy` (already forward-only,
   documented "non-overlapping or dst < src") applies directly with no new
   helper.
   `Insert(value, arr, index)` needs the tail to move *up* (dest > src) to open
   a gap — an ascending copy in that direction corrupts data (reads a source
   byte only after a wider destination write has already clobbered it), and
   `PXXMemCopy` explicitly does not support that direction. Two ways around it,
   neither implemented yet:
   - Write the new (n+1)-length buffer as a **second, independent allocation**
     (`SetLength` a fresh temp exactly like `Copy` does) and fill it with *two*
     `PXXMemCopy` calls from the *original* (unrelated, still-intact) buffer —
     `[0..index)` then `[index..n)` shifted by one — plus a single element
     store at the gap. Old buffer to new is never self-overlapping regardless
     of direction, so this sidesteps the landmine entirely at the cost of a
     full copy (same cost profile `Copy` already has, so no new complexity
     class). Then replace the array's handle with the new one (see point 1).
   - Or grow in place via the existing `SetLength` growth path first (which
     already reallocs to a fresh block), then do the shift as a **plain
     descending Pascal loop** (`for i := tailBytes-1 downto 0`) inside a new
     dedicated helper proc rather than through `PXXMemCopy` — avoids touching
     `PXXMemCopy` itself, but is a hand-rolled loop that wants its own test
     rather than reusing an already-proven primitive.

**Scope-cut precedent already in this codebase:** `Copy` itself is
"deliberately shallow" — a raw byte copy, so an array of a managed element type
(`AnsiString` / managed record) is not deep-copied/retained, documented as a
known, accepted limitation rather than a blocker (ir.inc:2308-2309). Whether
`Delete`/`Insert` should ship with the same shallow-only cut (matching Copy's
already-accepted scope, and this ticket's original acceptance bar would need
loosening to match) or hold out for the managed-retain/release the ticket's
`## Scope` section above asks for is exactly the kind of call this session's
own rule says to surface rather than decide solo overnight.

**Recommendation for whoever picks this up next:** implement the "second,
independent allocation" shape for `Insert` (reuses `Copy`'s exact template,
zero new correctness surface beyond an extra `PXXMemCopy` call + one element
store), start shallow-only (matching `Copy`'s precedent) to keep the first cut
Copy-sized rather than open-ended, and file the managed-element retain/release
as an explicit, separate follow-on ticket once the shallow shape is landed and
tested — same staged approach `Copy` itself took.

## Acceptance

`Delete`/`Insert` on a dynamic array shift + resize correctly (with managed
elements released/retained as appropriate); string forms unchanged; regression
tests; self-host byte-identical.
