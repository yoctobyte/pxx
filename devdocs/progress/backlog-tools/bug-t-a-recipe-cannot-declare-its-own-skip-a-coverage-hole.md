---
track: T
prio: 45
type: bug
status: backlog
found: 2026-09-06
found-by: frankS
owner: ""
blocked-by: []
summary: "A Makefile recipe that self-skips has no way to say its skip is a COVERAGE HOLE. `_self_skipped` returns the recipe's whole SKIP line, which always begins `<target>: SKIP`, and `SKIP_HOLE_PREFIXES` matches at position 0 — so a recipe self-skip can never be counted as a hole, by construction and on purpose. That is right for a recipe guarding its own optional probe and wrong for `test-zlib`'s `gcc oracle not found`, which is coverage the box is not providing on a job backing a public claim. Needs a channel from the recipe, NOT a looser match in the harness."
---

# A recipe cannot declare its own skip a coverage hole

## The mechanism, and why the current behaviour is deliberate

`_self_skipped` (tools/testmgr.py) reads the recipe's own `<target>: SKIP …`
line and returns it verbatim, so the reason survives into the report in the
words the recipe used. `skip_summary` then asks
`why.startswith(SKIP_HOLE_PREFIXES)` — and `why` starts with the target name,
so it can never match. Not an oversight: the comment above the tuple says
folding a recipe's own guard into corpus-absence is the seven-week
`(corpus absent)` bug that tuple was written to end. **Do not loosen the match.**

## Where it is nevertheless wrong

Two different things wear the same shape:

- **A recipe guarding its own optional probe.** `stb_sprintf_probe: SKIP (no
  library_candidates/stb)` — the recipe handles the absence, its jobmates are
  unaffected, and this is correctly not a hole.
- **A recipe declining because the BOX cannot provide coverage.**
  `test-zlib: SKIP — gcc oracle not found` is the same class as
  `host tool absent:` and `host dev dependency absent:` — the harness's own
  words for "this box is not providing this coverage". It is invisible in
  `skip_holes`, and `test-zlib` backs one of the two claims this project makes
  in public copy ("zlib matches the gcc oracle").

## What is wanted

A channel the recipe can use to classify its own skip, so the two cases above
are distinguishable at the source rather than guessed at by prefix. Shape is
open — a second marker line, or a documented reason prefix the recipe emits
after the target name, or a hole-declaring variant of the SKIP token. Whatever
it is, the harness must keep refusing to infer it.

## Provenance and scope

Found while fixing bug-t-corpus-regex-invents-phantom-tree (d6de711d1).
**NOT the cause of `skips: 7 / skip_holes: 2` on the 2026-09-06T18:37:24Z seven
report** — I attributed the five uncounted gtk jobs to this mechanism and that
was wrong. They carry `host dev dependency absent:`, a HARNESS reason from
testmgr.py:1849 that simply is not in the tuple; frankB corrected it and is
fixing that separately. None of those seven skips is a recipe self-skip. This
ticket is the residual question that survives that correction, with no instance
yet observed in a published report — `gcc` is present on both boxes today.
