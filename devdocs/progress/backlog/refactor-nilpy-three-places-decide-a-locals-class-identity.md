---
prio: 40
track: N
blocked-by: []
---

# Three separate places decide a NilPy local's class identity

- **Type:** refactor (root-cause cleanup behind a fixed bug)
- **Track:** N (`compiler/pyparser.inc`, Track N's own file)
- **Status:** backlog — filed 2026-08-08 out of
  [[bug-nilpy-local-reassigned-across-classes-keeps-one-static-class]]
- **Owner:** —

## The three

| site | what it does |
| --- | --- |
| `PyNoteLocalType` (~2820) | records one assignment's RHS against a local, widening via `PyWiden` |
| `PyCollectLocalsAST` harvest loop (~16900) | harvests the trial parse's syms, widening via `PyWidenBinding` |
| `PyCollectModuleLocalsAST` harvest loop (~17600) | the same loop again, for module scope |

They disagree in detail: two use `PyWidenBinding`, one uses `PyWiden`; the class
identity rule now has to be written out three times.

## Why this is worth a ticket

`root-cause-over-microfix`'s counting test says two mechanisms is a smell and
three is a design flaw, and this one has already cost a session. Fixing
"a local reassigned across two unrelated classes keeps one static class"
in the two harvest loops looked complete — the two-assignment repro passed —
and was silently undone by `PyNoteLocalType`, which read the cleared `RecCi` as
"no class known yet" and re-adopted one. It took a **three**-assignment repro
and a `PXXDBG=n.locals` reading (`o tk=22` → `o tk=6 rec=0`) to see it.

The `Poly` flag now papers over that by being sticky and checked in all three.
That works, but the next rule added to local typing has the same three-way
duplication waiting for it.

## Shape of the fix

One `PyBindLocalClass(ci, tk, rec)` that owns widening, class identity and the
`Poly` decision; the three sites call it. The two harvest loops differ only in
which constraint table they walk, so they should reduce to a shared helper
parameterised by that.

Watch for the fixpoint contract: the harvest loops report `changed` and re-run,
so the helper must return "did anything move" rather than setting a global, and
must be idempotent — the original bug here was a rule that oscillated and would
have hung the fixpoint if `Poly` had not been made sticky.

## Gate
`make test-nilpy` + self-host byte-identical, plus the tests named in the parent
ticket — especially `test_nilpy_rebind_across_unrelated_classes` (whose third
assignment is what catches a regression in exactly this area) and
`test_nilpy_with_name_reuse`.
