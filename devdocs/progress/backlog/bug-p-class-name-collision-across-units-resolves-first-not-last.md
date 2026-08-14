---
track: P
prio: 45
type: bug
summary: "Two units exporting the same CLASS name: pxx binds the first unit named, FPC binds the last. The routine half of this was fixed and gated (bug-p-uses-order-does-not-decide-which-unit-wins, done); classes were never done — name-resolution.md §2.2 says scope hiding is 'BUILT for routines, MISSING for types/classes'. Filed because two tickets already cite this slug and no such ticket existed."
---

# Class-name collisions across units resolve first-not-last

- **Type:** bug (FPC divergence, `compat` tag) — **Track P** (Pascal frontend;
  the resolution lives in the shared `symtab.inc`, so coordinate with A).
- **Filed 2026-08-14 by Track T**, on discovering that
  `bug-pascal-uses-clause-duplicate-name-resolves-first-not-last` is cited by
  two tickets and **does not exist as a file**.

## Why this had to be filed rather than just linked

[[decide-merge-variant-c-with-bare-name-collision]] was decided today on an
argument that rests on this ticket existing:

> *"the parity ticket is filed with a measured oracle repro, so nothing is being
> lost track of."*

It was not filed. `feature-a-one-exception-class-in-a-shared-unit` cites the same
slug. So the one thing that decision leaned on — that the exposure is tracked
elsewhere — was not true, and the decision was otherwise sound only because the
exposed case is synthetic. Filing it makes the argument true rather than
retroactively wrong.

## The divergence

Two used units export a class of the same name:

| | bare name under `uses a, b` |
|---|---|
| FPC | **b's** — the LAST unit named wins |
| pxx | **a's** — the first registered wins |

## The routine half is already done — this is specifically classes

[[bug-p-uses-order-does-not-decide-which-unit-wins]] (Track P, p60, **done**)
fixed exactly this for **routines**, with `test/test_shadow_last_uses_wins.pas`
and `test/test_shadow_first_uses_hidden.pas` covering both clause orders and
both call shapes, gated at `--tier limited` 1726/1726.

Classes were not included, and `devdocs/dev/name-resolution.md` §2.2 says so in
as many words:

> **Scope hiding — BUILT for routines, MISSING for types/classes**

So this is not a regression and not a fresh discovery; it is the unfinished half
of a job whose finished half is already proven, which is the best possible
starting position. **Read that ticket first** — it records a naive fix that was
measured to break the NilPy stdlib and the compiler's own self-compile, so the
shape of the answer is already constrained.

## Reachability

Today: **not reachable in practice.** The RTL has no duplicated class names, so
nothing collides. Merging variant C (sibling `Exception` classes in `pylib` and
`sysutils`) is what makes it reachable — and per that decision, only for a
program importing both, which is not a real NilPy program.

That is why this is p45 and not urgent. It should be fixed because the routine
rule already exists and types silently disagreeing with it is the kind of
inconsistency that costs an afternoon later, not because anything is broken now.

## Gate

Mirror the routine tests: two units exporting a class of the same name, both
clause orders, asserting FPC's answer — verified against the FPC oracle, not
against our own output. Then `name-resolution.md` §2.2 stops saying MISSING.
