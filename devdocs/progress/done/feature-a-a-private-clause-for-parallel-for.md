---
track: A
prio: 50
type: feature
status: done
found: 2026-08-31
found-by: frankA
owner: "frankA"
blocked-by: []
summary: "DONE. `private(v, ...)` on a `parallel for` gives each WORKER its own
  copy of v, seeded to zero/False/nil/'' and never written back -- reduction
  minus the combine, reusing the private-local machinery an inner `for`'s
  control variable already had. Scalars and AnsiString; arrays, records and
  classes are refused with a message naming the alternative. Closes the
  motivating shape: a per-iteration scratch variable had no race-free spelling,
  and the loop that must total 300000 gave 298051/298141/299650/299462/299233
  over five runs before the clause and 300000 over twenty after it. SEEDED where
  OpenMP leaves private uninitialised, and the seed is proven load-bearing by a
  compiler built without it. Verified x86-64/i386/aarch64/arm32; riscv32 refuses
  --threadsafe entirely and has no parallel rows."
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

## 2026-09-03 — landed

**The clause.** `private(v, ...)` parses in the same loop as `reduction(...)`,
so the two stack in any order and repeat. The names are resolved in the body
pre-scan that already handles an inner `for`'s control variable, which is where
the body's token span is known and where the capture list is built — so a
private is excluded from the capture list for free, and an inner `for` over a
variable already listed does not add a second entry.

**Both questions the ticket left open are answered, and the second one moved.**

*Seed value.* Zero / `False` / `nil` / `''`, as predicted — but the reason
turned out to be stronger than "managed types have no uninitialised state".
**An uninitialised local reads its stack slot, and a freshly-entered worker
frame is usually zeroes, so the unseeded behaviour is accidentally CORRECT most
of the time.** Measured: with the seed emission disabled in the compiler and
nothing else changed, the SEED row printed **11, not 0** — the Integer and the
Double came back dirty while the Boolean and the Char landed on zero bytes and
passed. Two of four components fired. That is why the test keeps all four with
different weights: which ones catch it is a property of the frame layout, not of
the defect. (Same shape as the `cdo_while_goto_entry` probes frankb-78 hit the
same day, from the other end.)

*Managed elements.* `AnsiString` works and is in. The worry about a per-worker
release was unfounded — the private is an ordinary local of an ordinary nested
procedure, so the RTL releases it at scope exit. Verified rather than assumed,
with `-dPXX_ALLOC_CENSUS`: 4000 iterations gave `allocs=10975 frees=10972
live=3`, and 16000 gave `allocs=45116 frees=45111 live=5`. Four times the work,
`live` flat — a per-iteration leak would have been proportional. An
`expect_same` row could not have seen this.

**What is NOT in, deliberately.** Arrays, records and classes cannot be private;
the refusal names the alternative (index a shared array by the loop variable,
which needs no clause). `firstprivate` — copying the enclosing value in — is not
offered and remains a separate ask.

**One incidental finding, and it cost a rebuild.** The seed for a `Char` is
`Char(0)` and not `Chr(0)`, because **`tkChr` greps as thoroughly live — six
backends test `-Ord(tkChr)` — and every one of those is an INTRINSIC ID stored
in `ASTIVal`; the lexer never emits `tkChr` as a token.** A stashed `tkChr`
therefore reaches the parser as something no expression arm accepts, and the
failure surfaces as `expected expression` **inside `lib/rtl/palthread.pas`**,
which is where the synthesized worker body lands — a file the statement under
edit never mentions. Noted at the site.

**Where it is tested.** `test/test_parallel_for_private.pas` — SCRATCH (the
motivating shape), TYPES (Integer/Double/Boolean/Char/Pointer), SEED, STR (a
managed private plus `SetLength`), and an OUTER row asserting the enclosing
variables are untouched, which is the whole difference from `reduction`. Wired
native + i386/aarch64/arm32 beside the reduction rows. All five new error paths
were exercised and each fires.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit b67d943eb.
