---
track: A
prio: 25
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
