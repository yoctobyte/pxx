---
track: T
prio: 35
type: feature
blocked-by: []
summary: "pasmith is integer/bool/char/string throughout, which left the constant evaluator's REAL path entirely unfuzzed — and that path was silently wrong until 8938aed7d (a const aliased to a real const yielded its IEEE bits as an integer; `const C: double = 3` stored 0.00; `= -3` stored Nan). Adds a const section in those shapes, folded by COMPARISON so no float formatting enters the oracle."
status: done
---

# pasmith: a `const` section for the real-typed constant evaluator

- **Type:** feature (fuzz grammar — Track T owns the tool)
- **Opened / done:** 2026-08-16
- **Prompted by:** the sweep behind `8938aed7d`, which found the underlying bug
  by hand and flagged it as "the one worth a rung". Attributed to the COMMIT
  rather than to a session -- more than one dev session was in flight.

## The blind spot

Every rung in this generator is integer, bool, char or string. Nothing has ever
emitted a `const` section, and nothing has ever emitted a real. So the constant
evaluator's real path had **no coverage at all** — and it was wrong in three
distinct ways (fixed 2026-08-16, `8938aed7d`):

| shape | what pxx stored |
| --- | --- |
| `const A = 3.14; B = A;` | B got the **IEEE bits as an integer**, `4614253070214989087` |
| `const C: double = 3;` | `0.00` |
| `const D: double = -3;` | `Nan` |

The evaluator was integer-only and recognised a real const only as a bare
literal token. Silent, and reachable from entirely ordinary code — the worst
combination, and precisely what a differential generator exists to catch.

## The rung

`--consts N` emits N groups covering all three shapes plus the integer-const
source:

```pascal
const
  ka0 = 3.0;
  kb0 = ka0;            { const aliased to a real const }
  kc0: double = 30;     { real-typed, integer literal }
  kd0: double = -30;    { ...and negative }
  ke0 = 30;
  kf0: double = ke0;    { real-typed, from an integer CONST }
```

Literals are **halves** (`n / 2.0`), so each is exact in binary and the check
below cannot be defeated by a representation argument. The point of this rung is
the evaluator, not float formatting.

## Folded by COMPARISON, never by formatting

```pascal
Mix(ord(ka0 > 2.9900) + 2*ord(ka0 < 3.0100));
```

Printing a double would drag decimal formatting into the oracle, where two
implementations may legitimately differ in digits — a divergence nobody owns,
which is the one thing that makes a fuzzer worthless (the same trap the
generator's existing notes call out for evaluation order and for `var`/`out`
aliasing). A comparison against a tight bracket answers the only question that
matters — *is the stored value right?* — and cannot manufacture that argument.

The Nan case falls out for free: `Nan > lo` and `Nan < hi` are both false, so a
Nan folds **0** where a correct value folds **3**.

## Validated against the bug itself

Same pattern as [[feature-pasmith-for-limit-rungs]], and again by accident: the
probe was first run against a binary predating `8938aed7d`.

| compiler | probe checksum |
| --- | --- |
| pre-fix | pxx `-2442907868338654835` vs fpc `8117996468627587049` — **DIFFER** |
| rebuilt at the fix | both `8117996468627587049` — **AGREE** |

So the comparison-fold detects the real bug on the buggy compiler and goes quiet
on the fix, which is the only validation that means anything for a new rung.

## Scope note — routine-local typed consts are NOT covered, deliberately

The same session reports a separate, still-open defect: a routine-local typed
const is re-initialised on every call (`const calls: Integer = 0; Inc(calls)`
prints 1 forever; a string-typed one does not compile). Their guidance was
explicit — the fix is not a microfix (the symbol is rolled back with the
routine's other locals, so a pending-init record at main time points past
SymCount; the C frontend's `CWrapStaticInitOnce` run-once BSS guard is the shape
to reuse) and **no rung is worth building until it lands**.

So this rung emits **program-level** consts only. Adding routine-local ones
today would produce a rung that diverges on ~100% of seeds against a known open
bug — exactly why `--intfs` and `--mptrs` are kept out of `--wide`. Revisit when
that ticket lands.

## In `--wide`

Folded in at 1, like `--checks`: it has no known divergence, and left out
nothing would run it since every real slice is `--wide`. `--wide --consts 0`
still turns it off. Both `--wide` implementations updated
(`pasmith.py` and `pasmith_run.WIDE_DEFAULTS`), and the knob is in the
`gen-args` header, so localisation still rebuilds the identical program —
round-trip re-verified on three seeds after adding it
([[bug-t-pasmith-gen-args-header-omits-half-the-rungs]]).

## Verified

- `pasmith_run.py --check 40 --wide`: 40 seeds, 0 rejected by FPC.
- `gen-args` round-trip byte-identical on seeds 3, 11, 42 under `--wide`.
- Generated programs agree between pxx and FPC.
- `pasmith_run.py --seeds 300-370 --wide` (rung on by default): **71 programs,
  0 divergences.**

## Follow-up filed

The accidental validation happened twice in one day, which is luck rather than
method. [[feature-t-pasmith-rung-selftest]] proposes making it deliberate —
proving a rung's fold observes its construct by MUTATING the generated program
rather than rebuilding an old compiler. The prototype in that ticket is this
rung: corrupting `kc0: double = 30` to `= 0` changes the checksum, so the fold
demonstrably sees the value.

## Log
- 2026-08-16 — resolved, commit c2806f0ea.
