---
track: T
prio: 40
type: bug
blocked-by: []
summary: "pasmith's self-describing `gen-args:` header was a hand-maintained format string that had drifted from the constructor: --intfs/--hier/--mptrs/--props/--exdtor/--clsm/--wide-p were all missing, and FOUR of those are set by --wide. localize() rebuilds the subject from that header, so on every wide seed it traced a DIFFERENT program (measured 1500 lines vs the original's 1770) and its trace diff described a program that never diverged."
status: done
---

# pasmith's `gen-args` header had drifted from the generator it describes

- **Type:** bug (fuzzer tooling) — **Track T**
- **Found:** 2026-08-16, while adding the `{$Q+}/{$R+}` rung
  ([[feature-pasmith-qplus-rplus-rungs]]) — the new knob would have inherited
  the same defect, which is how it surfaced.
- **Fixed in the same commit.**

## What was wrong

Every generated program carries a self-describing header:

```
  Reproduce with: tools/pasmith.py --seed 3
  gen-args: --vars 8 --funcs 3 --stmts 40 ... --modeprocs 2 }
```

`pasmith_run.localize()` reads it back (`gen_args_of`) and re-runs the
generator with `--trace` to rebuild the identical program, because the trace
diff is what names the diverging statement. The comment directly above it states
the contract: *"the seed alone must be enough to rebuild the identical program
(this is what makes a shrinker unnecessary)."*

The header was a hand-written format string listing thirteen knobs. The
constructor takes **twenty-one**. Missing: `--intfs`, `--hier`, `--mptrs`,
`--props`, `--exdtor`, `--clsm` and `--wide-p` — and `hier`, `props`, `exdtor`,
`clsm` are all set by `--wide`, the flag every real slice runs with.

## Measured

Generate with `--wide`, read the header back, regenerate from it, diff:

```
seed 3, --wide --checks 1 --stmts 40
  original rebuild : 1770 lines
  from gen-args    : 1500 lines     <-- a different program
```

So for any `--wide` seed, `localize()` compiled and traced a program that was
**not the one that diverged**. Whatever checkpoint it named was arbitrary, and
the `kind` it derived became the ledger SIGNATURE — so findings were being
deduplicated under labels taken from the wrong program.

Silent, and in the worst direction: a mislocalised finding still looks like a
finding.

## Root cause, and the fix

A hand-maintained second list. Adding a rung meant remembering a place that
nothing enforced, and six additions in a row forgot it.

Fixed by generating the header from a single sequence of `(flag, value)` pairs
covering every constructor knob, so adding one to the header is the same edit as
adding it to the generator. `pasmith_run.py` already had this shape — its
`GEN_FLAGS` is one list used for the repro line, the ledger and generation
alike, with a docstring explaining why (*"A repro line that does not reproduce
is worse than no repro line at all"*). The generator side simply never got the
same treatment.

Note the two lists still exist on opposite sides of the file boundary and can
drift again in principle; what stops it now is that each is a *list*, so an
omission is visible rather than buried in a `%` format.

## Verified

Round-trip is exact — generate, read the header, regenerate, byte-compare:

```
seed 3     rebuild IDENTICAL
seed 5     rebuild IDENTICAL
seed 11    rebuild IDENTICAL
seed 42    rebuild IDENTICAL
seed 90010 rebuild IDENTICAL
```

all with `--wide --checks 1 --stmts 30`.

## Consequence for past findings

Any pasmith finding whose localisation was taken on a `--wide` seed has a
**suspect statement attribution and therefore a suspect signature**. The
divergence itself was real — that comes from running the real program under two
oracles, which never used the header — so nothing needs un-filing. But a ledger
entry's `kind` may name the wrong construct, and two genuinely distinct bugs
could share a signature by accident.

Cheapest remedy if it matters: `--recheck` re-runs open ledger entries, and
re-localising them now produces correct kinds. Not done here, because the open
ledger is small and the entries are re-derived on the next sweep anyway.

Related: [[feature-pasmith-divergence-signature-granularity]] (the other half of
"the signature must name the right thing"), [[bug-t-pasmith-order-dependent-programs]]
(the repro-line version of this same lesson).

## Log
- 2026-08-16 — resolved, commit PENDING-COMMIT.
