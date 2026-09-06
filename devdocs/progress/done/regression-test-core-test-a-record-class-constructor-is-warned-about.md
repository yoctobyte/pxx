---
slug: regression-test-core-test-a-record-class-constructor-is-warned-about
prio: 70
track: P
type: regression
status: done
owner: frankB
created: 2026-09-06
title: "The row ignored its rc with make's `-` prefix, which the line-splitting harness never sees"
summary: "RESOLVED fb87d1ea0, and it was a defect in the ROW rather than in the test or the compiler. The test is a MUST-NOT-COMPILE case whose claim is the WARNING on the log, not the refusal: pxx rejects a parameterless record constructor for reasons unrelated to the ticket it guards, and that refusal arrives after the warning, so asserting it would make fixing that look like a regression here. The row therefore ignored its exit code -- with make's `-` prefix. Track T's harness splits a recipe into LINES and runs each itself, so the `-` is MAKE's syntax and never reaches the runner: the row exits 1 for the harness and 0 under make, i.e. it reds for everyone else and passes locally. First-ever run, no earlier passing sha, which is exactly the shape the auto-filer describes as 'a finding about the job, not a regression from the commits around it' -- and it was right. Fixed by moving the rc-ignoring inside the SHELL command (`|| true`), which both readers see. Verified by running the two lines by hand with no make in front of them: both exit 0. Filed by twatch against ad2735420d6b, a docs/tickets-only sha it correctly said could not be the cause.")
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_a_record_class_constructor_is_warned_about.pas /tmp/test_recclassctorwarn26 > /tmp/recclas`, which names `test/test_a_record_class_constructor_is_warned_about.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 1 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-core#src:test/test_a_record_class_constructor_is_warned_about.pas at ad2735420d6b in step 1/2, `./compiler/pascal26 test/test_a_record_class_constructor_is_warned_about.pas /tmp/test_recclassctorwarn26 > /tmp/reccla…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T09:42:27Z
- **Test source:** test/test_a_record_class_constructor_is_warned_about.pas
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_a_record_class_constructor_is_warned_about.pas`.
  ```
  ./compiler/pascal26 test/test_a_record_class_constructor_is_warned_about.pas /tmp/test_recclassctorwarn26 > /tmp/recclassctorwarn.log 2>&1
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_a_record_class_constructor_is_warned_about.pas'` at ad2735420d6b85ae25863b82ab3b591ca0282b31

## Range
> **The named sha `ad2735420d6b` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `ad2735420d6b`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## Resolved 2026-09-06 (frankB) — the row, not the test

`-./$(COMPILER) ...` ignores a failure **in make**. Track T's harness reads the
recipe and runs the lines itself, so the `-` — which is make's syntax, not the
shell's — never reaches the runner. The row therefore exits 1 for the harness and
0 under make: **it reds for everyone else and passes for its author.**

Changed to `... || true`, which is inside the shell command and visible to both
readers. Verified the way the harness runs it, by executing the two lines with no
make in front of them: both exit 0, and line 2's `grep` still fails if the
warning is absent.

**The auto-filer's own diagnosis was correct and worth not overriding.** It said
this was a first-ever run with no earlier passing sha, so no interval contains a
cause and every commit a range could name is equally innocent — *"a red here is a
finding about the job, not a regression from the commits around it."* That is
exactly what it was. It also said the named sha touches no buildable file and
cannot be the cause; also right.

Generalisable, and it is not about this row: **a recipe line whose exit code
means one thing to make and another to a line-by-line runner is a row that
passes for its author and fails for everyone else.** Anything conveyed by make's
syntax rather than the shell's — `-`, `@`, a `$(MAKE)` recursion, a line
continued into the next — is invisible to a harness that extracts lines. Where a
row deliberately ignores an rc, ignore it in the shell.
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit fb87d1ea0.
