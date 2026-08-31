---
track: U
prio: 60
type: decide
owner: ""
blocked-by: []
summary: "RULED 2026-08-31 by the owner: OPTION 1 -- seed from entropy at import, keep random.seed(n) for determinism. We follow CPython; the upward-compatibility charter is one-directional and settles it. This OVERRULES the ticket's own recommendation of option 2 (a PXX_RANDOM_SEED env var): CPython has no such knob for random, and the debuggability it protects is not being relied on -- MEASURED, which is what made this cheap. Five NilPy tests reference random; THREE draw values (not two -- see the correction below) and all three seed explicitly and assert CONTRACTS not values (test_nilpy_math_surface_and_random.npy:4 says so in as many words). So entropy seeding breaks no test, and the stated cost lands on ad-hoc debugging, whose fix is the one line of random.seed(n) a CPython programmer already writes. Unblocks bug-b-nilpy-random-is-never-seeded-and-its-first-draw-is-the-low-bound."
status: decided
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

---

# RULED 2026-08-31 — option 1, seed from entropy

Owner: *"the random seed question is trivial, we follow cpython in behavior...
instructions are clear."* They are: the charter is **one-directional** — code
that works on CPython must work here — and a program that shuffles a deck or
picks a random port depends on not getting the same answer twice, which is a
guarantee CPython makes and we currently deny.

## Why option 1 and not this ticket's own option 2

The recommendation above was option 2 — entropy plus a `PXX_RANDOM_SEED=n`
override, on the grounds that it loses nothing. **Overruled**, on a measurement
the ticket did not make.

Option 2 protects debuggability. Nothing is relying on it:

- **Five** NilPy tests reference `random`.
  `test_nilpy_from_import_binds_provided_names`, `test_nilpy_bare_import_is_python`
  and `test_nilpy_import_spellings` exercise **import mechanics only** and never
  draw a value.
- The two that draw — `test_nilpy_math_surface_and_random` and
  `test_nilpy_by_name_list_params_take_a_str` — **seed explicitly** and assert
  contracts, not values. The first says so at line 4: *"the random half asserts
  the CONTRACT, because the sequence is deliberately not..."*, and checks
  `random.seed(42)` → `random.random() == a`, `3 <= randint(3,7) <= 7`,
  `choice(xs) in xs`. The second: *"The random VALUES are not asserted — the
  generator is not CPython's."*

So entropy seeding **breaks no test**, and option 1's stated cost — a failure
involving randomness no longer reproducing from source alone — lands on ad-hoc
debugging, where the remedy is the one line of `random.seed(n)` a CPython
programmer already writes. CPython itself ships `PYTHONHASHSEED` and no
equivalent for `random`, so option 1 is also the closer match to the thing we
are compatible with. A second mechanism, with a second place to document it, in
the name of a property nothing uses, is not worth it — and it is cheap to add
later if it ever bites.

## What to build

Extract the entropy source `builtin.pas`'s `Randomize` already has (per-arch
`clock_gettime`, with its documented bare-target fallback) and seed `PyRandState`
from it at module init. **Extract, do not duplicate** — the mechanism exists.
`random.seed(n)` keeps working unchanged and remains the way to pin a stream.

Replace the comment above `PyRandState` in `compiler/builtin/pylib.pas` in the
same commit. It currently argues for the fixed seed, and its defence — *"a
program that DEPENDS on the difference is depending on the stream"* — answers a
different objection: nobody may rely on the exact sequence, which is true and is
not what was at stake. Leaving it in place would leave the repo arguing with
itself.

## Note on why this was a ticket

Correct to escalate, over-priced at 60. The fixed seed was a **documented
decision**, not a slip, and this repo does not let an agent overrule one of those
as a bug fix. What would have shrunk it: the charter it collides with is
unambiguous and quoted in this very ticket, and the test-suite cost — the only
thing that could have made it genuinely hard — took two greps to rule out.
**Escalate the conflict; price it after checking the cost.**

## Unblocks

[[bug-b-nilpy-random-is-never-seeded-and-its-first-draw-is-the-low-bound]]
(blocked/, parked on this answer). Its own finding stands and is not re-opened:
the leading `1` from `randint(1, 100)` was **not** a second defect — it is the
fixed state's first draw happening to be ≡ 0 mod 100.

*Ruled 2026-08-31 by the owner; test-dependency measurement by frank-user.*

## CORRECTION 2026-08-31 — my census undercounted, and the reason matters

frankB, implementing this, found that
`test_nilpy_from_import_binds_provided_names` **does** draw a value:

```python
from random import seed, randint
...
seed(1)
print(randint(5, 5))
```

I had put it in the "import mechanics only, never draws" group. **Three tests
draw, not two.**

**Why the census missed it, precisely:** I grepped `random\.seed`, which matches
only the *dotted* spelling. This file uses `from random import seed, randint` and
then a bare `seed(1)` — so the pattern **structurally could not match the very
spelling the file exists to test.** A from-import test, invisible to a
dotted-form grep. The instrument could not fail for the population it was aimed
at, which is this repo's own recurring shape.

**The conclusion is unchanged and for a better reason than I gave.** The file is
safe under entropy seeding because it seeds explicitly *and* because
`randint(5, 5)` is degenerate — one possible value — not because it never draws.
Stated correctly: **all three drawing tests seed explicitly**, which is what makes
the import-time default irrelevant to them.

## The open item is closed, negative

I flagged that I had not checked whether `pydiff.py` or the fuzz harness generate
random-using programs. They do not. `tools/pydiff.py` states the rule for its own
corpus in a comment near line 199 — *"Keep it deterministic (no time, no
randomness, and SORT anything set-derived — set order is unspecified and
CPython's own varies per run)"* — spot-checked here. `fuzz.sh` mutates Pascal
sources, whose `Randomize`/`RandSeed` surface this change does not alter
behaviourally.

## Landed

`4fa9f66e5` (frankB) — `PXXEntropy64` extracted from `builtin.pas`'s `Randomize`
(interface-declared; `Randomize` is now one line over it, no second syscall
table), `pylib.pas` seeds `PyRandState` in the unit's `initialization`, no env
var. Seeding is unconditional at init rather than lazy on first draw: CPython is
not conditional either, and a have-I-been-seeded flag would have to get the
`seed()` interaction right for no gain.

A **third** stale comment was corrected that neither of us knew about: the
riscv32 note in the moved block said *"Randomize is the only caller, so a program
that never randomizes never issues it"* — now false, since pylib's init issues
`clock_gettime64` at startup for any program pulling pylib. It still cannot reach
a bare ESP boot, because pylib uses builtin and builtin does not compile there,
but that is the reason and it had never been written down.
