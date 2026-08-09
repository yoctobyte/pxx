---
track: U
prio: 20
type: chore
summary: "Verify that ACATS (Ada) and the NIST COBOL-85 suite are actually fetchable and under a licence we can vendor — both were asserted from memory when costing the Legacy frontends, neither was checked"
---

# Are the Ada and COBOL conformance corpora actually usable?

- **Type:** chore (research — one afternoon, no code)
- **Track:** U → Track **L** (Legacy) once that lane exists
- **Status:** rainy-day — matches its parents; pointless unless one of them moves.
- **Owner:** —
- **Related:** [[idea-ada-frontend-bare-metal-fit]],
  [[idea-cobol-frontend-feasibility-costing]]

## Why this exists

Both Legacy costings lean on a claim that was made **from memory and never
verified**: that Ada and COBOL are unusually well supplied with public
conformance corpora, which is most of what makes them attractive targets. If
that is wrong, the "gradeable claim" argument for both weakens considerably, so
it should be checked before either idea is taken seriously — not after.

## What to establish

1. **ACATS** (Ada Conformity Assessment Test Suite) — current home, how it is
   distributed, and its licence. Specifically: may we vendor it into
   `library_candidates/` the way the gcc c-torture corpus was vendored, or is
   it fetch-at-build-time only?
2. **NIST COBOL-85 test suite** — believed public domain and still the base
   GnuCOBOL validates against. Confirm it is still obtainable, and in what
   shape (the original tapes were... of their era).
3. **Differential oracles** — confirm **GNAT** and **GnuCOBOL** are packageable
   on the dev boxes, since the plan for both languages is the CPython-oracle
   pattern that drove Track N, not just suite-passing.
4. Note anything about *scope*: a conformance suite proves conformance, not
   that real code compiles. Real COBOL leans on IBM Enterprise extensions and
   is overwhelmingly proprietary, so the real-world corpus problem is likely
   the opposite of Python's. Worth recording what actually exists in the open.

## Precedent for how to vendor one

`tools/c_torture_harvest.sh` — vendored corpus, compile each case, cross-check
candidates against the reference compiler, and **never auto-dismiss a candidate
because the reference disagrees**. Same shape applies to both languages.

## Acceptance

A short written answer per corpus: obtainable yes/no, licence, vendorable
yes/no, and whether the oracle compiler installs cleanly. Update both parent
tickets with the result — including if the answer is "no", which is the more
useful outcome to know early.

## Log
- 2026-08-09 — filed. Flagged as unverified at the time the parents were
  written; this is the ticket that stops the assumption hardening.
