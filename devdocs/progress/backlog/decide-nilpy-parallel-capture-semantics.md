---
summary: "DECIDE: NilPy parallel for-in capture model — what's private, what's shared, how reductions read"
type: decide
prio: 5
---

# DECIDE — NilPy parallel for-in: private/shared/reduction semantics

- **Type:** decide (Track U — a semantics fork only the user settles).
- **Status:** backlog
- **Opened:** 2026-07-17.
- **Unblocks:** [[feature-nilpy-parallel-for-in]].

## The fork

The shared parallel-for runtime captures loop-body variables **by reference (shared)** —
concurrent writes race (documented, not a heap bug:
[[project_parallel_for_byref_capture_shared_write_race]]; private = function locals /
disjoint slots). Pascal's `parallel for` inherits Pascal's variable model. **NilPy's
variable model differs** — Python variables are function-scoped with late binding, and a
Python programmer's mental model of a `for` loop body is *not* "these vars are shared
across iterations." So NilPy must **choose** a mapping, and the choice is user-visible.

## Options

1. **Iteration-private by default, explicit shared/reduction opt-in** (Python-idiomatic).
   Each iteration gets private copies of body-local names; writing a shared result
   requires either a disjoint index (`out[i] = ...`) or a declared `reduction(op, var)`.
   Matches what a Python user expects; safest. Cost: the lowering must classify names
   (private vs the loop's disjoint-index target vs reduction) and allocate per-worker
   slots.
2. **Shared by reference (mirror Pascal), race is the user's problem.** Thinnest
   lowering — reuse Pascal's model verbatim. But it hands a Python audience a footgun the
   language never had, and "works in the sequential loop, races in the parallel one" is
   exactly the silent-bug class this project hunts.
3. **Restrict v1 to provably-safe bodies** — only allow disjoint-index writes
   (`out[i]`) and declared reductions; reject a body that writes a shared scalar. Compiler
   enforces safety; widen later. Most conservative; smallest correct surface.

## Recommendation

**(3) for v1, evolving toward (1).** Ship the safe subset (disjoint-index +
reduction, reject the rest with a clear diagnostic) — it can't produce a silent race,
matches the runtime's proven-safe patterns, and defers the harder name-classification of
(1) until there's demand. (2) is rejected: a Python-shaped race is a parity trap.

## Also decide (small)

- **Surface syntax:** decorator (`@parallel`), a `parallel for x in …` keyword, or a
  builtin (`parallel(range(n))`). Recommendation: a decorator or `parallel` builtin reads
  most Python-ish and avoids a new statement form.

Resolving this unblocks [[feature-nilpy-parallel-for-in]].

## PARKED — deliberately last (user, 2026-07-20)

Not blocked on any one ticket, and intentionally not given a `blocked-by` edge:
this waits on the whole substrate settling (int/bigint and the object model are
in flux as of this date), and there is no single commit that will say "now".
Revisit when the dust has settled and the picture is clearer — a vague later,
on purpose.

**Do not read the low prio as "small and easy to grab".** The user's framing:
the feature is *trivial to implement* and expensive to live with — it "would
spark bugs under our ass at every clock cycle". The cost is not building it,
it is every latent race it legitimises afterwards, across a language whose
users have never had to think about them (CPython's GIL made `list.append` and
`d[k] = v` effectively atomic; true parallelism removes that, so correct
CPython code silently races). Cheap to add, permanent to own.

Whoever picks this up later: re-read the fork above before writing any code,
and confirm with the user that the substrate is actually settled.
