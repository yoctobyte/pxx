---
slug: decide-nilpy-deepcopy-over-the-container-subset
title: "Should copy.deepcopy exist over the container subset, or stay deliberately absent?"
track: U
type: decide
prio: 40
status: open
found: 2026-08-29
found-by: claude-N
---

# `copy.deepcopy`: implement over the subset, or keep the loud absence?

Two documents in this repo disagree, and I am not the right one to settle it
because one of them is a previous author's explicit, reasoned decision.

## The disagreement

`lib/rtl/mimic_copy.py` says, in a section headed **DELIBERATELY ABSENT**:

> `deepcopy`. It is not a bigger version of this — it needs the memo table and
> the same introspection protocol to recurse through arbitrary objects, and a
> "deepcopy" that only went one level down would be a shallow copy under a name
> that promises otherwise. A caller who needs it gets a loud unresolved-name
> error.

[[feature-nilpy-stdlib-coverage-gaps-measured]] lists it as remaining work:

> `copy.deepcopy` is the one that needs a real recursive walk over the variant
> container tags.

Both were written in good faith and they cannot both be acted on.

## What I think the prior decision was arguing against

The docstring's objection is to a deepcopy **that only goes one level down**.
That is not the only option, and I do not think it is the one the ticket meant.

A *fully recursive* deepcopy over the same subset `copy.copy` already serves —
list / dict / set / frozenset / tuple, immutables by identity, **raising loudly
on anything else** — is a different proposition. It is not a shallow copy under
a false name; it is a real deep copy whose domain is stated, which is precisely
the contract this file already keeps for `copy.copy` and which
`devdocs/dev/python-compat-tiers.md` endorses ("a shim that states its subset
and fails loudly beats one that approximates").

## Options

**A. Implement it over the container subset, raising outside it.**
Matches `copy.copy`'s existing contract exactly, and covers what callers
overwhelmingly mean by `deepcopy` — nested config dicts and lists. Needs a memo
table keyed on `id()` (which NilPy has) so a self-referential container
terminates instead of recursing forever. Cost: perhaps 40 lines of NilPy in a
file that is already NilPy.
*Risk:* a caller who deepcopies a structure containing one user object gets a
raise where CPython succeeds — a loud failure, not a wrong answer.

**B. Keep it absent.** The status quo and the prior author's call. An
unresolved-name error is the loudest possible signal, and nobody is misled.
*Risk:* an ordinary CPython program that deepcopies a nested dict does not run,
and that is the upward-compatibility direction NilPy promises.

**C. Implement it and ALSO handle user objects shallowly**, i.e. recurse
containers, return anything else by identity. **I recommend against this** — it
is the exact thing the docstring warns about, and it fails silently.

## Recommendation

**A**, and then delete the "DELIBERATELY ABSENT" paragraph rather than leaving
two documents disagreeing. The subset contract is already this file's design;
extending it to a recursive walk keeps the contract and closes a real gap.

But it overrides a documented decision, so it is the owner's call and not mine.

## What is NOT in question

Nobody is proposing the one-level-down deepcopy the docstring rejects. If the
answer is A, it is a genuinely recursive walk with a memo table, or it is not
worth doing.
