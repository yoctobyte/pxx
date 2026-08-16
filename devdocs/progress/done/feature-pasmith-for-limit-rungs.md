---
track: T
prio: 40
type: feature
blocked-by: []
summary: "pasmith's `for` rung emitted only LITERAL bounds, so it structurally could not express either of the two for-loop bugs found by hand on 2026-08-16 (limit re-evaluated per iteration; a limit at the counter type's maximum never terminating). Added both shapes; validated by reproducing both bugs on the pre-fix compiler and reporting clean on the post-fix one."
status: done
---

# pasmith: `for` limits that are variables, and limits at the type maximum

- **Type:** feature (fuzz grammar — Track T owns the tool)
- **Opened / done:** 2026-08-16
- **Prompted by:** the Track A+C+P+N session's Pascal oracle sweep, which found
  both bugs BY HAND and asked whether a rung could reach them. It could not.

## The blind spot

The `for` rung generated exactly one shape:

```python
lo = rnd.randint(0, 3)
hi = lo + rnd.randint(0, 4)
out = ["for %s := %d to %d do" % (lv, lo, hi), ...]
```

Literal bounds, both small. That cannot express either bug fixed in
`dfc3b7449`:

1. **A limit that is a VARIABLE the body mutates.** The limit must be evaluated
   ONCE, before the loop. pxx re-emitted the limit subtree per iteration — the
   same value-node defect as the case selector — so `for i := 1 to Limit`
   called `Limit` four times for three iterations, and a limit variable written
   in the body changed the trip count.
2. **A limit at the counter type's MAXIMUM.** `for i := 2147483645 to
   2147483647` never terminated: the bottom test incremented past the limit and
   wrapped.

Both are cheap to generate. The grammar simply had a blind spot exactly where a
bug lived, which is the only kind of blind spot that matters.

## The two shapes, and why each is safe to generate

**`forvarlimit`** — the limit is a longint global, **seeded to a small literal
immediately before the loop**:

```pascal
g3 := 3;
for li0 := 0 to g3 do
begin
  ...body...
  g3 := g3 - 1;
end;
```

The seeding is load-bearing: an unseeded global holds whatever the program put
there, and `for li0 := 0 to <two billion>` is not a test, it is a hang.

The mutation **decrements, never increments**. Under correct semantics the limit
is fixed and the decrement is inert; under the re-evaluation bug the trip count
*shrinks*, so a regression still terminates and reports as a DIVERGENCE rather
than as a timeout. An incrementing mutation would turn the same bug into a hang,
which is a strictly worse signal for the same coverage.

**`formaxlimit`** — longint's maximum, so it needs no new declaration (the loop
variables are already longint):

```pascal
for li0 := 2147483645 to 2147483647 do ...
```

Three iterations when correct; non-terminating if the bottom test regresses,
which `pasmith_run` reports as `pxx-timeout`. That is the RIGHT verdict here and
not the slow-vs-hung confusion of
[[bug-t-csmith-harness-reports-slow-as-a-timeout]]: pasmith programs are bounded
by construction, so a timeout can only mean a hang. csmith's are pathological by
construction, so its timeout could mean either — which is why the two harnesses
correctly treat the same symptom differently.

Both are tagged with their own kind, so they sign distinctly in the ledger
rather than hiding inside the generic `for`.

## Validated against the bugs themselves — by accident, and conclusively

The first differential run was made against a compiler binary built BEFORE
`dfc3b7449` (pulled the fix, forgot to rebuild). That turned into the best
possible test:

| compiler | result |
| --- | --- |
| pre-fix binary | **23 divergences**, including `pxx-vs-fpc_forvarlimit` x8 and `pxx-timeout_formaxlimit` |
| rebuilt at the fix | **0 divergences** |

So the rung reproduces both real bugs, names them with the right construct, and
does not false-positive on the fix. A fuzzer rung cannot be better validated
than by catching the known bug and going quiet on its remedy — and this one was
never tuned against those programs, because it was written before the run.

Worth noting the mislocalisation it also showed: several pre-fix findings signed
as `pxx-timeout_assign` / `_case` / `_if` rather than `_formaxlimit`, because the
hang is attributed to the innermost statement executing when the clock ran out
rather than to the loop containing it. Not chased — the bug is fixed and the
signature was still actionable — but it is the same family as
[[feature-pasmith-divergence-signature-granularity]] and worth knowing if a
future hang reads oddly.

## Verified

- `pasmith_run.py --check 40 --wide`: 40 seeds, 0 rejected by FPC.
- `pasmith_run.py --seeds 1-30 --wide`: 30 programs, 0 divergences (post-fix).
- Shape coverage over 40 seeds: 40 seeds carry a variable limit, 34 a max limit.

Related: [[feature-pasmith-qplus-rplus-rungs]],
[[bug-t-pasmith-gen-args-header-omits-half-the-rungs]].
- `pasmith_run.py --seeds 200-280 --wide`: **81 programs, 0 divergences.**

## Log
- 2026-08-16 — resolved, commit 3f6d5ca85.
