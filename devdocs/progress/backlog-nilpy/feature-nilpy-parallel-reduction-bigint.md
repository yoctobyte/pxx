---
track: N
prio: 5
type: feature
blocked-by: [feature-nilpy-parallel-for-in]
summary: "Opt-in arbitrary-precision reduction for `parallel for`. v1 keeps per-worker partials in the promo-int inline tier and raises at the spill point; this adds the real bignum path, which is correct but anti-scales because every bignum op takes the global heap spinlock."
---

# Opt-in bignum reduction for `parallel for`

Follow-up to [[feature-nilpy-parallel-for-in]], whose v1 deliberately refuses
this case. Decision and measurements:
[[decide-nilpy-parallel-capture-semantics]].

## What v1 does, and why

Every integer accumulator in NilPy infers as a **promotable int** — measured
with `PXXDBG=n.locals`: `total += i` gives kind 28, and there is no annotation
escape (`a: int = 0` is also 28; so is `b = b + i`). Correct for Python
semantics, but it puts the commonest reduction on the one type that is not a
machine scalar.

`promocore.pas`'s header states the heap tier *"costs a pack/unpack per
operation"*, and line 1546 calls the repack *"profiled as the dominant"* cost.
So every bignum addition packs, allocates and unpacks — and under `--threadsafe`
each allocation takes the global heap spinlock. A parallel integer sum therefore
**anti-scales**: more workers, more contention on one lock, in a loop whose whole
purpose was to scale.

So v1 keeps the per-worker partial in the **inline tier** and **raises** at the
spill point — a check already paid for, native speed, loud failure instead of a
silent cliff. Documented as *"native int, unless you ask for bigint in advance."*

("Promote in advance" was considered and measured out: the heap representation is
serialised and repacked per operation, so pre-promoting only enters the expensive
tier sooner. Strictly worse than lazy promotion.)

## What this ticket adds

The explicit opt-in — a program that genuinely needs arbitrary precision in a
parallel reduction can ask for it and accept the cost.

- **Surface:** a kwarg in the same clause list, e.g.
  `parallel(sum=total, bigint=True) for i in range(n):`. Exact spelling is open;
  keep it in the policy/reduction kwargs rather than inventing a second syntax.
- **Semantics:** per-worker partials are full promo-ints; the fold under
  `PXXReduceLock` does bignum arithmetic.
- **Docs must state the cost plainly:** correct, but does not scale — the heap
  lock serialises your workers. A user who opts in should not be surprised.

## Worth exploring first

Per-worker `Int64` partials with overflow detection, promoting **only at the
fold**, would give arbitrary-precision results at native speed for the
overwhelmingly common case where no single worker's partial overflows. That may
make this ticket's slow path nearly unnecessary.

Stated as a direction, **not** a recommendation — it has not been measured, and
the session that filed this got caught asserting exactly this class of thing.
Measure before building.

Related: `promocore.pas` names *"stage 4's check elision and range analysis"* as
what restores native speed for values that never leave the inline tier. A
reduction accumulator is precisely such a value, so that work and this pull the
same direction — check whether it lands first and makes this cheaper.

## Gate

`make test-nilpy` green + self-host byte-identical; `compiler/builtin/**` if the
fold touches promocore, in which case `stabilize-fast` + `make pin`. A test whose
sum genuinely exceeds 64 bits and matches CPython's answer.
