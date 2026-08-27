---
track: U
prio: 60
type: decide
owner: ""
blocked-by: []
summary: "CPython's `random` seeds from entropy at import; NilPy's starts from a fixed constant, deliberately, so a failing run reproduces. That is a real trade-off and it collides with the upward-compatibility rule. Recommendation: seed by default, keep determinism behind an explicit opt-in."
status: backlog
---

# Does NilPy's `random` seed itself at import?

- **Track U** (decision). Raised 2026-08-27 while working
  [[bug-b-nilpy-random-is-never-seeded-and-its-first-draw-is-the-low-bound]],
  which is parked on this answer.
- **Not a discovered oversight.** `compiler/builtin/pylib.pas` states the choice
  and its reason in a comment, so changing it is overruling a decision, not
  fixing a slip — which is why it is here and not in the bug.

## The fork

`compiler/builtin/pylib.pas`, above `PyRandState`:

> *"The state starts at a fixed value rather than a clock reading: a program
> that never calls seed() then reproduces exactly, which is what makes a failure
> reportable. CPython seeds from entropy instead, and a program that DEPENDS on
> the difference is depending on the stream, which neither implementation
> promises."*

Measured consequence, on pinned v388:

```python
import random
for i in range(8):
    print(random.randint(1, 100))
```

prints `1 80 73 48 91 14 77 100` on **every run, forever**. (The leading `1` is
not a separate defect: the first draw from the fixed state is a constant that
happens to be ≡ 0 mod 100 and mod 5. With a different range the first value is
ordinary — `randint(0, 1000000)` opens with `793785`. The bug ticket originally
claimed two defects; there is one.)

## Why it is not clear-cut

**For the current behaviour.** A failing run reproduces from the source alone,
with no seed to capture — genuinely valuable, and it is why the choice was made.

**Against it, and this is the part the comment does not cover.** The charter is
*"if code works on CPython, it must work on NilPy"*. A program that shuffles a
deck, samples a corpus, jitters a retry, or picks a random port is not
"depending on the stream" — it depends on **not getting the same answer twice**,
which CPython guarantees by seeding at import and NilPy currently denies. That
class of working CPython program is broken here, silently, and the failure looks
like a logic bug in the user's code.

The comment's defence answers a different objection (nobody may rely on the
exact sequence — true, and not what is at stake).

## Options

1. **Seed from entropy at first use; keep `random.seed(n)` for determinism.**
   CPython's own contract. A program that wants reproducibility writes the one
   line CPython programs already write. `builtin.pas`'s `Randomize` already has
   the per-arch `clock_gettime` entropy, with a documented bare-target fallback,
   so the mechanism exists and would be extracted rather than duplicated.
   *Cost:* a NilPy failure involving randomness no longer reproduces from source
   alone.
2. **Seed from entropy, but honour an env var / flag** (`PXX_RANDOM_SEED=n`)
   that pins it. Keeps both properties; costs one small mechanism and a place to
   document it.
3. **Keep the fixed seed, and document the divergence** in
   `devdocs/dev/nilpy-semantics-divergences.md`. Cheapest, and it makes the
   behaviour findable — but that document is for things a working CPython
   program *cannot observe*, and this one observes it immediately, so the entry
   would be the first of a different kind.

## Recommendation

**Option 2**, falling back to 1 if the flag is not worth the mechanism. The
upward-compatibility rule is the stronger of the two claims, and it is the one
stated as a charter; debuggability is a real but recoverable loss, and option 2
does not even lose it. Option 3 puts an observable behavioural difference in a
document defined as being for unobservable ones.
