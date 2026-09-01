---
track: A
prio: 50
type: feature
status: open
found: 2026-08-31
found-by: frankA
owner: ""
blocked-by: []
summary: "`parallel for` has `reduction(op: v)` and nothing else, so a captured local the body ASSIGNS cannot be made per-worker. That is not a defect -- docs/library/concurrency.md documents capture-by-reference and says an unguarded shared write is a data race -- but it means a whole class of loop body cannot be written at all: the natural `s := ''; SetLength(s, 8); use(s)` scratch variable has no race-free spelling with a captured scalar. A `private(v)` clause giving each worker its own copy (initialised empty/zero, discarded at the end) would close it; the reduction machinery already builds exactly this, a per-worker private plus a combine, so private is that minus the combine."
---

# A `private(...)` clause for `parallel for`

Split out of
[[bug-a-a-parallel-for-body-shares-one-captured-string-across-all-workers]],
which was resolved as not-a-defect: the shared-by-reference semantics are
documented and correct. This is the missing *expressiveness*, not a bug.

## Why it is worth having

`test_setlen_in_parallel_for_body.pas` had to be pinned to a single worker
(`parallel(pdChunked, n 1)`) to be deterministic, because the shape it exists to
test — a per-iteration scratch string — has no race-free spelling. A body
wanting scratch storage today must either declare it as a dynamic array indexed
by the loop variable (works, and is what the file's second loop does) or give up
concurrency.

## Why it should be cheap

`reduction(op: v)` already does the hard half. Per
`pasparser_stmt.inc`, it allocates a private `__pfred<K>` accumulator per
worker, seeds it with an identity, and folds under `PXXReduceLock` at the end.
**`private(v)` is that machinery minus the combine step** — allocate the
private, seed it, never fold. The clause parser, the capture resolution and the
private-local declaration are all in place.

Two questions to settle when someone picks this up, neither blocking:

- **Seed value.** Empty/zero is the obvious default. OpenMP's `private` leaves
  it *uninitialised* and has `firstprivate` for copy-in; given this dialect's
  managed types, an uninitialised AnsiString is not a thing we want, so
  empty/zero is probably the only sane option and `firstprivate` is a separate
  ask.
- **Managed elements.** `reduction` explicitly refuses non-scalars
  (`only scalar variables are supported (not dyn-array/string)`). `private` has
  no such excuse — a private AnsiString is the motivating case — so it needs a
  per-worker release at loop end.

## Raised 25 → 50 on 2026-09-02: it is not "cannot be written", it is "quietly wrong"

Filed as a missing capability — a scratch variable with no race-free spelling.
Measured while fixing
[[bug-a-a-nested-for-loop-in-a-parallel-for-body-is-a-compile-error]], the same
shape also COMPILES and returns a short answer:

```pascal
parallel(pdChunked) for i := 0 to n - 1 reduction(+: acc) do
begin
  j := 0;                                    { j: an enclosing local }
  while j < 3 do begin acc := acc + 1; j := j + 1; end;
end;
```

n = 100000, so `acc` must be 300000. Five runs: **299674, 299015, 295718,
298575, 296181.** Every worker increments the same `j` through the same
pointer, so iterations are lost, and nothing anywhere says so.

The docs are not wrong — concurrency.md does say capture is by reference and an
unguarded shared write is a race — but a documented trap that produces a
plausible number is the expensive kind. The sibling `for` spelling used to be a
compile error, which at least sent people looking; it is now correct, and that
removes the last signpost pointing at this.

The inner-`for` fix builds most of what is needed: a pre-scan that names
variables needing a per-worker copy, a private declaration in the worker's own
`var` section with the right type token, and exclusion from the capture list so
no `^` is appended. `private(v, ...)` is that machinery driven by a clause
instead of by the `for <ident> :=` pattern.
