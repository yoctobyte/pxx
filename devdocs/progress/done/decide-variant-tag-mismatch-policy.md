---
track: U
prio: 60
type: decide
---

# Decide: what a Variant unbox does when the tag does not match the target

Raised while landing [[bug-a-nilpy-variant-element-not-usable-as-scalar]]
(commit 8bd1ac4c). The ticket flagged this as a real decision; I shipped a
defensible default rather than blocking, so **this is a confirm-or-change,
not a blocker**.

## RESOLVED IN SHAPE 2026-07-20 — helpers are now per-language

The user's call: *"we can just craft our own when needed — python obviously
needs other helpers. as long our AST is shared, i don't care for duplicating
helpers because of syntax variations."*

So this is no longer one policy question. Commit d3754ee3 split the helpers:
NilPy uses pylib's `pyvar_to_int/float/bool/char`, Pascal keeps builtin.pas's
`VariantTo*`, and `ir.inc` picks the set under `PyProgramMode`.

- **The NilPy half is SETTLED**: Python's rules, TypeError on a str/object in
  a numeric slot, total truthiness for bool. Nothing further to decide.
- **The Pascal half is now a separate, smaller question** — see the compat
  note at the end.

The options table below is kept because it is still the argument for the
NilPy answer.

## The fork

`VariantToInt64` / `VariantToDouble` / `VariantToBool` / `VariantToChar` in
`compiler/builtin/builtin.pas` must do *something* when the payload's tag is
not the requested class. Two families of case:

1. **Numeric <-> numeric <-> bool <-> char.** Not contentious: both Pascal's
   Variant and Python's numeric tower coerce. Shipped as coercion
   (VT_DOUBLE -> Trunc for an integer target, etc.). No decision needed.
2. **STRING payload, numeric target** (`i = xs[0]` where the element is
   `"ab"`). This is the genuine fork.

## Options for case 2

| | behaviour | argument for |
| --- | --- | --- |
| **A (shipped)** | halt with a runtime error | CPython raises TypeError here. Loud beats silent; this whole bug class was silent garbage, so inventing a number would re-create it in a new place. |
| B | parse the text (`Val`) | Pascal's Variant is historically coercive; convenient in scripty code. |
| C | yield 0 | never crashes; maximally silent — I'd argue against. |

## Recommendation

**Keep A**, and revisit only if a corpus program actually wants B. A is the
conservative direction: it can be relaxed to B later without breaking any
program that works today, whereas shipping B and tightening to A later breaks
working code.

Note the asymmetry deliberately left in place: the *other* direction (numeric
payload, STRING target) keeps `VariantToStr`'s existing coercive behaviour —
that is shipped semantics `str()` depends on, not mine to change here.

## If the answer is "keep A"

Close this and no code moves. If it is B or C, the change is confined to the
three `else` branches in the `VariantTo*` helpers.

## The PASCAL half — MEASURED and CLOSED 2026-07-20 (commit 5287bdd7)

An earlier revision of this ticket said "fpc is not installed on this box".
**That was wrong** — fpc is at /usr/bin/fpc and `make fpc-check` had been
passing all session. My probe program used `Exception` without `uses SysUtils`,
so it failed to compile, and a `|| echo "fpc absent"` reported that as a
missing toolchain. Corrected here rather than left standing.

With the actual oracle run:

| expression | FPC | pxx before | pxx now |
| --- | --- | --- | --- |
| `i := v`, v='42' | 42 | halt | 42 |
| `i := v`, v='abc' | EVariantError | halt | error |
| `d := v`, v='2.5' | 2.50 | halt | 2.50 |
| `b := v`, v='' | EVariantError | False (!) | error |
| `b := v`, v=0.0 | FALSE | False | False |

So Pascal wanted **B** (coerce, error on junk) — the opposite of what NilPy
wants, which is precisely why the helper split had to come first. Note row 4:
`VariantToBool` was returning Python truthiness for Pascal, a divergence that
was invisible while one helper served both languages.

Both halves are now settled and this ticket can close:
- **NilPy** — Python's rules, TypeError on str/object in a numeric slot.
- **Pascal** — FPC's rules, measured.

Lesson worth keeping: I nearly filed "unverified, needs a box with fpc" on a
box that had fpc. Check the tool, not the exit code of a compound command.

## DECISION (recorded 2026-07-20, moving to done)

- **NilPy:** Python's rules — TypeError on a str/object in a numeric slot,
  total truthiness for bool. Landed via the per-language helper split
  (`d3754ee3`): NilPy uses pylib's `pyvar_to_int/float/bool/char`.
- **Pascal:** FPC's rules, measured against the real oracle — coerce a numeric
  string, `EVariantError` on junk (`5287bdd7`). Pascal keeps builtin.pas's
  `VariantTo*`; `ir.inc` picks the set under `PyProgramMode`.
- **Decided by:** the user's call that per-language helpers are fine
  ("we can just craft our own when needed ... as long our AST is shared").

Both halves settled, no residue, no dependents. Closing.

*Note on the reference above: this section originally cited commit `19442857`,
which exists in no branch of this repo. The real commit is `5287bdd7`,
identified by matching the measured table. Corrected rather than left
standing — a ticket citing a commit nobody can look up is worse than one
citing none.

I considered making `check` validate cited shas and decided against it: 125 of
464 commit citations across `done/` (26%) do not resolve, and this repo rebases
constantly (`git pull --rebase` is the norm), which REWRITES shas. So most
phantoms are benign history rewrites, not fabrications, and the rule would be
125 false alarms on day one. Measured, then dropped.*

## Log
- 2026-07-20 — resolved, commit 5287bdd7.
