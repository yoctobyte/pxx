---
track: B
prio: 60
type: bug
owner: ""
blocked-by: []
summary: "`import random` then `random.randint(1,100)` produces the SAME sequence on every run — CPython seeds from OS entropy at import and NilPy never does. The first draw is also always the low bound: randint(1,5) and randint(1,100) both open with 1."
status: backlog
---

# NilPy's `random` is never seeded, and its first draw is the low bound

- **Type:** bug (Track B — `lib/rtl/random.pas`) — **silent wrong behaviour**,
  no diagnostic. Two defects in one repro; they may share a cause.
- **Found:** 2026-08-27 while probing the eight `lib/rtl/*.pas` units that share
  a name with a Python stdlib module
  ([[bug-n-an-attribute-on-an-unresolved-import-degrades-to-a-bare-name]]).
  `random` is one of the units that *works*, which is why nobody looked at what
  it returns.

## Repro

```python
import random
for i in range(8):
    print(random.randint(1, 100))
```

| | |
| --- | --- |
| run 1 | `1 80 73 48 91 14 77 100` |
| run 2 | `1 80 73 48 91 14 77 100` — identical |
| CPython | a different sequence each run |

## Two separable defects

1. **Never seeded.** Python's `random` module seeds itself from OS entropy when
   it is imported; Pascal's `Randomize` is an explicit call, and the NilPy
   binding kept Pascal's rule. So a program that works on CPython — a shuffle, a
   sample, a retry jitter, a test fixture that wants variety — is deterministic
   under NilPy. That is squarely the upward-compatibility rule
   (`devdocs/dev/nilpy-semantics-divergences.md` is for things a working CPython
   program *cannot* observe; this one it observes immediately).

   Seeding on import is the fix, not documenting the call: `random.seed(n)` for
   a *deliberately* reproducible sequence stays available and is what a program
   that wants determinism already writes.

2. **The first draw is always the low bound.** `randint(1, 5)` opened with `1`
   and `randint(1, 100)` opened with `1`, in every run. A first value pinned to
   the bottom of the range is the signature of state that is still zero when the
   first number is drawn — consistent with (1), but worth confirming separately,
   because if seeding alone fixed it the first draw would merely become
   *unpredictable* rather than *uniform*, and a generator whose first output is
   biased is worse than one that is merely deterministic.

## Note on scope

`lib/rtl/random.pas` is a real three-tier entropy library (HW instruction / OS
CSPRNG / PRNG fallback), so the quality of the underlying stream is not what is
in question here — the binding is. Check where the NilPy `random.*` names bind
and whether anything calls the unit's initialiser before the first draw.

## Gate

Two runs of the repro produce different sequences; the first value of
`randint(1, N)` is not systematically `1` across a batch of runs; and
`random.seed(k)` twice in one program still reproduces the same sequence.
