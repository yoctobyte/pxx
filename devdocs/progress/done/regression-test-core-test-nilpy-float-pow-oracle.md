---
status: done
---


## TRIAGED AND FIXED 2026-08-16 — both were mine, both from the same commit pair

`cannot read input file: test/test_nilpy_float_pow_oracle.npy` — the file never
existed. The `**`-via-Power prototype patch carried a Makefile assertion for a
test it did not also carry, and applying the prototype (`6a4fa40ae`) brought the
assertion in without the file. My own regression test for that work is
`test/test_nilpy_pow_matches_cpython.npy`, which covers the same ground (all
five spellings, both refusals, the integer `**`), so the phantom block is
removed at both Makefile sites rather than a second test invented for it.

Worth the note for whoever applies a banked prototype next: `git apply` of a
patch that edits the Makefile can reference files the patch does not add, and
`gate.sh quick` cannot see it — the assertion lives in a suite the quick tier
does not run. Check `git status` for untracked test files the patch's Makefile
hunks name.

## Log
- 2026-08-16 — resolved, commit a8a1cb9c1.
