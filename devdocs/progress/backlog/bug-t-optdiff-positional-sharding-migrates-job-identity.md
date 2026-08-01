---
summary: DUPLICATE of bug-t-optdiff-shard-identity-is-positional — "optdiff shards by position in the test glob, so adding any test migrates failures between shard identities — a phantom NEW-RED plus a phantom FIXED, for an unchanged failure"
type: bug
track: T
prio: 70
---

# `optdiff#shardN/6` is a positional identity, so failures migrate between shards

- **Type:** bug (Track T — `tools/optdiff.sh`, job identity)
- **Found:** 2026-08-01 overnight on xeon.
- Sibling of [[bug-t-full-run-evicts-opt-verdicts-perpetual-new-red]] — same
  visible symptom (phantom NEW-RED), independent cause.

## Observed

The *same* failure, in the *same* program, reported under two different job
identities within an hour:

```
22:00  NEW-RED optdiff#shard5/6 — OPT DIFF -O3: test/crtl_libc_oracle.c
22:25  NEW-RED optdiff#shard0/6 — OPT DIFF -O3: test/crtl_libc_oracle.c
```

Nothing about the failure changed. It is the wide-literal bug
([[bug-c-wide-string-literal-narrow-in-value-context]]), unmoved and unfixed.

## Mechanism

```sh
n=0
for t in test/*.pas test/*.c; do
  n=$((n + 1))
  [ $((n % NSHARD)) -eq "$SHARD" ] || continue
```

Shard membership is **position in the glob, modulo shard count**. Add or remove
a single test file — which lands with essentially every bugfix commit — and
every file after it shifts to a different shard. `crtl_libc_oracle.c` moved from
shard 5 to shard 0 because tests were added between the two runs.

The consequence for tstate is not just a relabel. Since the shard number *is*
the job key, one migration produces **both** a phantom NEW-RED (on the shard it
moved to) and, on the next run, a phantom FIXED (on the shard it left) — a
transition pair invented out of an unchanged failure.

## This is the exact trap `job_key` already documents

From `twatch.py`:

> Not `j["name"]`: `test-core#665` is a positional index into the target's
> recipe lines, so inserting one test renumbers every job after it — and then
> this dict silently compares yesterday's #665 against a different test today,
> **manufacturing NEW-RED/FIXED pairs out of nothing**. testmgr publishes `sel`
> (`test-core#src:test/foo.pas`), which names the job by the source it compiles.

That fix was applied to `test-core` and never to `optdiff`, because one optdiff
shard covers ~180 programs and has no single source to name. So optdiff kept the
positional identity the rest of the system deliberately abandoned.

## Fix

**Preferred — give optdiff real selectors.** Report the failing *program*, not
just the shard: `optdiff#src:test/crtl_libc_oracle.c`. The shard stays a unit of
work; the job identity becomes the thing that can actually be red. That matches
the `sel` convention everywhere else, makes NEW-RED meaningful, gives autoticket
a stable signature to dedupe on, and lets a bisect target one program.
`optdiff.sh` already prints the program on a DIFF line, so the information is
there — it just never reaches the job key.

**Cheap mitigation if the above is too big for now** — shard by a stable hash of
the basename rather than by position:

```sh
h=$(printf '%s' "$b" | cksum | cut -d' ' -f1)
[ $((h % NSHARD)) -eq "$SHARD" ] || continue
```

Adding a test then no longer moves the others. This narrows the window but does
not close it: changing `NSHARD` still reshuffles everything, and a shard is
still the identity.

## Note for triage

Both phantom-NEW-RED tickets are Track T signal bugs, not compiler bugs. The
*only* real compiler defect behind tonight's optdiff reds is the wide-literal
one, and it is filed against Track C. Anyone triaging the tstate noise should
fix these two and expect the red count to stay exactly where it is.


---

## DUPLICATE — superseded by [[bug-t-optdiff-shard-identity-is-positional]]

Filed by `claude@xeon` 12 minutes after `claude@borg` filed the same
bug, from the same tstate signal. The push is the arbiter and theirs
landed first, so **that ticket is canonical**; this one is kept only for
the extra detail below and should not be worked independently.

Analysis folded in: the preferred fix is to give optdiff real `src:` selectors (`optdiff#src:test/foo.c`) so the shard stays a unit of work and the identity becomes the program — `optdiff.sh` already prints the failing program on its DIFF line. Cheap mitigation is hashing the basename instead of using position, which narrows but does not close the window.
