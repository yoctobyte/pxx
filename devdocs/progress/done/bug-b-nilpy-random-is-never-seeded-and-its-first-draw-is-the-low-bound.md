---
track: N
prio: 60
type: bug
owner: frankB
summary: "FIXED — `import random` then `randint(1,100)` gave the SAME sequence every run because PyRandState started at a fixed literal. Now seeded from PXXEntropy64 (extracted from builtin.pas's Randomize) in pylib's initialization; random.seed(n) still pins the stream."
status: done
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


---

## 2026-08-27 — PARKED on a Track U decision, and my own filing corrected twice

### There is ONE defect here, not two

I filed "the first draw is always the low bound" as a second, possibly separate
defect. It is not. Measured across four ranges on v388:

| call | first two draws |
| --- | --- |
| `randint(0, 1000000)` | `793785 13824` |
| `randint(1, 100)` | `1 80` |
| `randint(1, 5)` | `1 5` |
| `randint(0, 999)` | `700 679` |

One fixed first draw R from the unseeded state, and R happens to be ≡ 0 mod 100
and ≡ 0 mod 5 (consistent with R ≡ 700 mod 1000, which the fourth row shows
directly). With a range that does not divide it the first value is ordinary. So
the "biased first draw" is an artefact of the fixed seed, and fixing the seed
fixes both rows. Nothing else is wrong with the generator.

### It is in the wrong file, and the wrong track

I wrote "Track B — `lib/rtl/random.pas`". `random.randint` does not come from
that unit at all: the frontend maps `random.randint` to `pyrandom_randint` in
**`compiler/builtin/pylib.pas`** (see the dotted-name table in `pyparser.inc`).
`lib/rtl/random.pas` is the Pascal three-tier entropy library and is not
involved. Re-tracked to **N**.

### And the behaviour is DELIBERATE, which is why this is parked

`pylib.pas` states the choice and its reason above `PyRandState`: a fixed start
means a failing run reproduces from the source alone. That is a real argument,
and changing it is overruling a decision rather than fixing a slip.

`devdocs/dev/autonomy.md`'s rule is escalate, don't guess. Filed as
[[decide-does-nilpy-random-seed-itself-at-import]] with the fork, the three
options and a recommendation (seed by default, keep determinism behind an
explicit opt-in). This ticket is blocked on it.

The implementation, once decided, is small and already scoped: `builtin.pas`'s
`Randomize` holds the per-arch `clock_gettime` entropy with a documented
bare-target fallback, so the fix is to EXTRACT that into a shared
`PXXEntropy64` and seed `PyRandState` lazily on first draw — not to write a
second copy of the syscall table. `test_nilpy_math_surface_and_random` calls
`random.seed(42)` first and asserts the contract rather than values, so it is
unaffected either way.


---

## 2026-08-31 — FIXED (frankB), per the owner's ruling

Ruling: `decided/decide-does-nilpy-random-seed-itself-at-import`, option 1 —
seed from entropy at import, keep `random.seed(n)` for determinism. This
**overruled this ticket's own recommendation** of an opt-in env var
(`PXX_RANDOM_SEED`); that knob was NOT built, and CPython ships no equivalent
for `random`, so option 1 is also the closer match to the thing we are
upward-compatible with.

### What landed

- **`compiler/builtin/builtin.pas`** — the per-arch `clock_gettime` block was
  EXTRACTED out of `Randomize` into `function PXXEntropy64: Int64`, declared in
  the interface. `Randomize` is now `RandSeed := Cardinal(PXXEntropy64)`. No
  second copy of the syscall table, which is what would have rotted.
- **`compiler/builtin/pylib.pas`** — `PyRandState := PXXEntropy64` in the unit's
  initialization section. Unconditional, not lazy-on-first-draw: CPython is not
  conditional either, and a have-I-been-seeded flag is the part that would have
  to get the interaction with `seed()` right.
- The comment above `PyRandState` that argued FOR the fixed seed is replaced in
  the same commit — it defended against "the exact sequence differs from
  CPython's" (true, unfixable, harmless) rather than the objection that
  mattered, which is that a program depends on not getting the same answer
  twice.
- The riscv32 comment inside the extracted function said "Randomize is the only
  caller, so a program that never randomizes never issues it". That is no longer
  true — pylib's init issues it at startup for any program pulling pylib — so it
  is corrected in the same commit. (It still cannot reach a bare ESP boot:
  pylib `uses builtin`, which does not compile there.)

### Gate — all three criteria met, on compiler 9a425370eca2

| criterion | result |
| --- | --- |
| two runs differ | four runs: `87 70 51 …` / `78 54 63 …` / `8 9 83 …` / `63 30 69 …` |
| first draw not systematically `1` | 87, 78, 8, 63 |
| `seed(k)` twice still reproduces | `True` + identical list `[204, 292, 859, 765, 251]` across three separate runs |

Plus, because this touches `builtin.pas` (every frontend) and pylib (which
`--tier quick` does not sweep):

- **Pascal canary** — `Randomize` still varies per run; `RandSeed := 7` still
  reproduces `23 9 80 39 54` every time.
- `test_nilpy_math_surface_and_random` and
  `test_nilpy_by_name_list_params_take_a_str` — the only two NilPy tests that
  DRAW a value — both match their `.expected`.
- `test_nilpy_import_spellings` and
  `test_nilpy_from_import_binds_provided_names` — exit 0, output stable across
  two runs. (`from_import` does draw, via `seed(1); randint(5, 5)` — a
  degenerate range.)
- `test_nilpy_bare_import_is_python` fails to compile, identically under
  `pinned`: it is a negative test asserting a diagnostic. Pre-existing, unrelated.
- `tools/gate.sh quick` GREEN; `make compiler/pascal26` converged after 2 rounds.

### The one open item from the handoff, now closed

Whether `tools/pydiff.py` or the fuzz harness generate random-using programs:
they do not. `pydiff.py:199` states the rule for its own corpus in the comment —
*"Keep it deterministic (no time, no randomness, and SORT anything
set-derived)"* — and `fuzz.sh` mutates Pascal sources, whose
`Randomize`/`RandSeed` surface is behaviourally unchanged by this commit.

## Log
- 2026-08-31 — resolved, commit 4fa9f66e5.
