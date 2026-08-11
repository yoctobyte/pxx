---
summary: "NilPy parallel for-in — lower a marked for-loop to the shared PXXParallelFor runtime"
type: feature
prio: 5
blocked-by: []   # was decide-nilpy-parallel-capture-semantics — DECIDED 2026-08-11
---

# NilPy parallel for-in

- **Type:** feature (Track N — Nil-Python frontend: pyparser + Python→IR lowering).
- **Status:** backlog (blocked on the semantics decision)
- **Owner:** —
- **Opened:** 2026-07-17, from the parallel-for readiness review.
- **Related:** [[decide-nilpy-parallel-capture-semantics]] (the private/shared model),
  [[feature-parallel-for-scheduling-policy]] (the runtime this rides),
  [[project_parallel_for_byref_capture_shared_write_race]] (the capture hazard).

## Why it's small — the hard half is done

The runtime substrate is complete and **frontend-agnostic**: `lib/rtl/palparallel.pas`
exposes `PXXParallelFor(lo, hi, body, ctx)` + policy variants `PXXParallelForP/PP`
(load-aware scheduler) + `reduction(op: v)` (per-worker partial folded under a combine
lock). The parallel-race bugs are closed (`bug-a-parallel-for-aarch64-multi-capture`
done; `...managed-string-race` rejected). No Track A / shared-internals change is needed
— this is a NilPy lowering that emits an ordinary runtime call plus a synthesized worker.

## Scope

1. **Surface** — a NilPy opt-in for a parallel for-loop (decorator / keyword / builtin;
   the syntax is decided alongside [[decide-nilpy-parallel-capture-semantics]]).
2. **Worker synthesis** — turn the loop body into a `TParForBody` procedure capturing the
   loop variable through `ctx`, emit `PXXParallelFor(lo, hi, @worker, ctx)`. Pascal does
   this in the shared `parser.inc` (`ParseParallelFor`), but that path is Pascal-specific;
   NilPy needs its own synthesis in `pyparser.inc`.
3. **iterable → range** — `for i in range(n)` maps directly to `lo/hi`. Arbitrary
   iterables (lists) fan by index (`0..len-1`, body indexes the iterable) — v1 may
   restrict to `range()` and widen later.
4. **`--threadsafe` requirement** — the default heap/ARC/console runtime is not
   thread-safe; a NilPy program using this must opt in (mirror the Pascal error).

## Acceptance

- A NilPy program with a parallel for-in over `range(n)` runs, uses multiple workers,
  and produces correct results for a disjoint-write body (e.g. fill `out[i]`).
- A reduction pattern (sum) works via the runtime's `reduction`.
- Gate: `make test-nilpy` green + self-host byte-identical + cross where a target runs it.
  Land only green.

## Non-goals (v1)

- Not arbitrary-iterable parallelism (range-first).
- Not new runtime capability — reuse `palparallel` as-is.
- Capture/reduction *semantics* are decided in [[decide-nilpy-parallel-capture-semantics]],
  not here.

## PARKED — deliberately last (user, 2026-07-20)

Not blocked on any one ticket, and intentionally not given a `blocked-by` edge:
this waits on the whole substrate settling (int/bigint and the object model are
in flux as of this date), and there is no single commit that will say "now".
Revisit when the dust has settled and the picture is clearer — a vague later,
on purpose.

**Do not read the low prio as "small and easy to grab".** The user's framing:
the feature is *trivial to implement* and expensive to live with — it "would
spark bugs under our ass at every clock cycle". The cost is not building it,
it is every latent race it legitimises afterwards, across a language whose
users have never had to think about them (CPython's GIL made `list.append` and
`d[k] = v` effectively atomic; true parallelism removes that, so correct
CPython code silently races). Cheap to add, permanent to own.

Whoever picks this up later: re-read the fork above before writing any code,
and confirm with the user that the substrate is actually settled.

---

## UNBLOCKED 2026-08-11 — the semantics are decided; still parked by choice

[[decide-nilpy-parallel-capture-semantics]] is settled and moved to `decided/`.
Read it for the reasoning; the design is summarised here so the implementer needs
one file. Background on the threading model:
`devdocs/dev/threading-model.md`.

**The prio stays low on purpose.** The decision is made; the *parking* is not
lifted. The user's framing is unchanged — trivial to implement, expensive to own
— and this is an X-tag extension (CPython has no parallel `for`, so nothing is
missing without it). Confirm with the user before starting.

## The design, settled

**Surface** — Pascal's `parallel for`, transliterated, with `parallel` as a
**soft keyword** (Python's own precedent: `match`/`case`/`type`, PEP 634):

```python
parallel for i in range(n):
    out[i] = i * 3

parallel(workers=4, cap=50) for i in range(n):      # policy, as real kwargs
parallel(sum=total, max=best) for i in range(n):    # reductions, same clause list
```

Reduction names are Python's own: `sum`/`prod`/`any`/`all`/`min`/`max`, mapping
onto the ops `ParseParallelFor` already accepts (`+`/`mul`/`or`/`and`/`min`/`max`
— **verified**, no runtime gap). Explicit only: do NOT infer a reduction from
`total += x`, because float addition is not associative and the result would
vary with worker count.

**Capture: BY REFERENCE (shared)** — Pascal's model, and the faithful one.
Python has no per-iteration scope (a `for` body's names are the function's
names — the closure-in-a-loop gotcha), so iteration-private capture would invent
a scoping rule Python lacks. Safety comes from the explicit per-loop opt-in, the
explicit reduction clause, [[feature-nilpy-threadsafe-containers]] and the docs
— not from a private-by-default model.

**Reductions, v1:** the per-worker partial stays in the promo-int **inline
tier**; reaching the spill point **raises**. Every integer accumulator infers as
a promotable int (measured: `total += i` → kind 28, and `a: int = 0` does not
escape it), and the heap tier packs/allocates/unpacks *per operation*, so a
bignum partial would anti-scale on the heap spinlock. Arbitrary precision on
request is [[feature-nilpy-parallel-reduction-bigint]]. Float, and `max`/`min`/
`any`/`all` on ints, are plain scalars and free.

**Also settled:** `--threadsafe` required (mirror the Pascal error); v1 is
`range()` only; x86-64 only, because `--threadsafe` is; and **`i` after the loop
is unspecified** — document it, do not leave whatever the last worker wrote.

## Tests this needs

- The disjoint-write shape from `test_parallel_for_lang.pas`, in `.npy`.
- **The soft-keyword test**: a NilPy program with a `def parallel(x)` and a
  variable named `parallel`, both still working. `test_parallel_policy_lang.pas`
  is the Pascal precedent and it exists for a reason.
- A reduction of each supported op; a float sum; an integer sum that stays inline.
- An integer sum that overflows the inline tier → the diagnostic, not a wrong
  answer and not a silent crawl.
