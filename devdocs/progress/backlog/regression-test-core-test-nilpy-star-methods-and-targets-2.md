---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_nilpy_star_methods_and_targets.npy /tmp/test_nilpy_starm26`, which names `test/test_nilpy_star_methods_and_targets.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_star_methods_and_targets.npy at 18f97d8f5f1f in step 1/2, `./compiler/pascal26 test/test_nilpy_star_methods_and_targets.npy /tmp/test_nilpy_starm26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-05T23:36:52Z
- **Test source:** test/test_nilpy_star_methods_and_targets.npy tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_nilpy_star_methods_and_targets.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_star_methods_and_targets.npy /tmp/test_nilpy_starm26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_star_methods_and_targets.npy'` at 18f97d8f5f1f45d26582b7ec7ff0b23dcbbd688c

## Range
> **The named sha `18f97d8f5f1f` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `18f97d8f5f1f`, last good `81a10ecb3dba`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:47: error: no overload of take matches these arguments
(tail)
pascal26:47: error: no overload of take matches these arguments
  near: )  print ( b . >>> take ( 1 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## TRIAGE 2026-09-06 (frank-coordinator) — the range contains exactly one commit touching the NilPy parser

**Track N stands**, guessed from the failing step, which names a `.npy` source.

Of the commits in `81a10ecb3dba..18f97d8f5f1f` that touch buildable files, **exactly one
touches `compiler/pyparser.inc`**:

```
cf3d904cb  fix(N): the NilPy copy of the record-cast stamp, and the census that says there were THREE readers
```

**First place to look**, and the author (frankA) has the context: it is the NilPy sibling
of a record-cast stamp fix, minting a real alias row where the arm previously wrote
`ASTIVal := 0`.

**Stated as elimination with its assumption named:** *"the only commit touching X"* is
sound only if the defect is in X. The range also touches `symtab.inc`, `defs.inc`,
`pasparser_call.inc`, `pasparser_decl.inc`, `pasparser_expr.inc` and
`pasparser_stmt.inc` — a shared-symtab change reaches the NilPy frontend too. This
narrows the search; it does not name the cause.

**Note the named sha is a docs-only commit** (the ticket header already says so): the
tested sha is the upper bound of an untested range, not a candidate.

## CORRECTION 2026-09-06 (frank-coordinator) — the narrowing above named the wrong commit, and the caveat named the right file

**`cf3d904cb` is exculpated, by a control and not by an argument.** frankA reverted its
`pyparser.inc` hunk alone and rebuilt; the binary moved (`896c2938958d` ->
`6f0b6a730035`, so the revert demonstrably took effect) and **the failure reproduced
unchanged**. One rebuild, and it settles the question the grep could not.

**The cause is `a79ea9af6`** (`fix(P): the single-candidate method gate checks its
arguments, at zero measured cost`), fixed and pushed as `0967a3ce9`. The single-candidate
gate argument-checks BEFORE `PyPackStarArgs`, so `def take(self, a, *rest, **kw)` called
as `b.take(1, 2, 3)` presented three Integers against a declared slot list of `a`, a LIST
and a DICT -- the shape the callee sees AFTER packing. **The pairing was wrong, not the
types: both sides were right about their own list and nobody was comparing the same one.**

**Why the narrowing missed it, stated as the instrument's failure mode rather than as bad
luck.** *"Exactly one commit touches `pyparser.inc`"* is a true statement that answers a
different question: it locates the only change to the frontend's OWN parser, and the
defect was in the callee machinery every frontend funnels through. The triage above lists
`pasparser_call.inc` and `symtab.inc` by name in its own caveat -- `a79ea9af6` touches
both. **The hedge was on the correct half and the search still went to the narrow arm
first, because a named single candidate reads as a lead and a named file list reads as
boilerplate.** A file-narrowed range wants its shared-machinery arm searched FIRST when
the failing frontend is not the one the range's frontend-specific commit belongs to.

**And the general form, which is frankA's and is worth more than this ticket:**

> **A shared-machinery change needs a corpus per FRONTEND, not per test count.**

`a79ea9af6` measured zero change across the Pascal corpus (1581/286, a 0-row diff),
conformance (381/2 with an identical failure list) and fgl (7/7), and carried a
discrimination control showing the same census differs from the pin on 56 rows -- so the
zero was real. **NilPy is in none of those three populations.** The rigour was spent on
making one population's zero trustworthy; the gap was that there were four populations.
`compiler/pasparser_call.inc`, `symtab.inc` and the AST/IR are reached by C, NilPy, Rust
and Zig as well as Pascal, and a one-line probe per frontend costs under a second -- the
argument CLAUDE.md already makes for marshalling changes, generalised to any callee
change.

The fix is on origin; this ticket still wants its `resolve`.

## Log
- 2026-09-06 — the seven watcher saw `test-core#src:test/test_nilpy_star_methods_and_targets.npy` GREEN at 0967a3ce9d05 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-nilpy-star-methods-and-targets-2`, not `regression-test-core-test-nilpy-star-methods-and-targets`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
