---
prio: 70
track: P
status: done
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_stackless_gen.pas /tmp/test_stackless_gen26`, which names `test/test_stackless_gen.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_stackless_gen.pas at cf9b14600039 in step 1/2, `./compiler/pascal26 test/test_stackless_gen.pas /tmp/test_stackless_gen26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T07:26:35Z
- **Test source:** test/test_stackless_gen.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_stackless_gen.pas`.
  ```
  ./compiler/pascal26 test/test_stackless_gen.pas /tmp/test_stackless_gen26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_stackless_gen.pas'` at cf9b14600039c2f62d7251b0e05330fb74827be9

## Range
> **The named sha `cf9b14600039` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `cf9b14600039`, last good `e7a805d13a09`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:144: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/target.
(tail)
pascal26:144: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/target.
  near: , ' ' ) ; writeln ; >>> end . unit 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-04 — the seven watcher saw `test-core#src:test/test_stackless_gen.pas` GREEN at 95f60ce71ad7 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-stackless-gen-2`, not `regression-test-core-test-stackless-gen`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## Closed 2026-09-04 — fixed at HEAD, verified by running the job's own comparison

Re-verified at HEAD `0d090cd1d`, compiler sha256 `1968c7a7da57`, as the ticket's
own staleness banner asks. Both steps of the recipe pass:

- step 1/2, the step this was filed on — `./compiler/pascal26
  test/test_stackless_gen.pas <out>` — exits 0.
- step 2/2 — output diffed against the exact expected string in `Makefile:10887`
  — **identical**, all nine lines.

Consistent with frankb-78's `203b8a8e8` (synthesised try/finally in the token
pre-scan), which is the plausible fix; I did not bisect to confirm attribution,
so treat the cause as likely rather than established.

**Two traps worth recording, because both nearly closed this wrongly in
opposite directions.**

The ticket names step 1/2 as the failing step. Step 1 is the COMPILE, and it
passes now — so "is the failing step fixed?" answers yes while saying nothing
about step 2, which is where the actual assertion lives. An auto-filed
regression names the step that reported the failure, not the step that tests
the behaviour, and closing on the named step alone would have been a green
about the wrong half of the recipe.

Going the other way, my own first read said the output was missing its last
three lines — because I had printed it through `head -6`. The truncation was in
my instrument, not the program. It answered correctly about the first six lines
and I read it as the whole output. Running the job's real comparison is what
settled it; a partial view of the right data is as misleading as the wrong data.

`track: P` was GUESSED from the failing step's path, as its own banner says, and
was never corrected. Recorded here so the guess is not mistaken for a finding by
anyone reading the `done/` entry.
