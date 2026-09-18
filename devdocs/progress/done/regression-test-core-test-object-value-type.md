---
prio: 70
track: P
status: done
---

> **Track guessed as P from the FAILING STEP** — line 8 of 9, `! ./compiler/pascal26 test/test_object_value_constructor_error.pas /tmp/test_object_value_constructor_error26 > /tmp/tes`, which names `test/test_object_value_constructor_error.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 5 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **The SLUG names `test_object_value_type`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `test_object_value_constructor_error`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_object_value_type.pas at cc03b4a51933 in step 8/9, `! ./compiler/pascal26 test/test_object_value_constructor_error.pas /tmp/test_object_value_constructor_error26 > /tmp/te…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-17T16:06:33Z
- **Test source:** test/test_object_value_type.pas tools/expect_same.sh +3
- **Failing step:** line 8 of 9 of the job's recipe; it names `test/test_object_value_constructor_error.pas`.
  ```
  ! ./compiler/pascal26 test/test_object_value_constructor_error.pas /tmp/test_object_value_constructor_error26 > /tmp/test_object_value_constructor_error.log 2>&1
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_object_value_type.pas'` at cc03b4a51933a51b3e30c3334797c209f534504f

## Range
> **The named sha `cc03b4a51933` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `cc03b4a51933`, last good `d0cad59b99e3`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-46993/test_object_value_type26  [code=73496B  data=4832B  bss=46660B  procs=152]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolution (frankB, 2026-09-18)

**Not a regression. Stale paperwork, and the watcher was right to fire.**

The cause is `efe06a903` (2026-09-17 16:00:02Z, Track P), which deliberately
made `constructor` and `destructor` legal on an old-style `object`: pxx
hard-errors on BOTH routes by which an `object` can acquire a VMT — an
ancestor, and a `virtual`/`dynamic`/`override`/`abstract` directive — so every
`object` that reaches the member loop is VMT-less by construction and a
constructor on one is semantically a plain method. It measured that against
FPC's own `versioncmp.pas:29`, `cgbase.pas:376` and `cmsgs.pas:46`, added its
own rows and fixtures, and left behind the row asserting the opposite:

```
! ./$(COMPILER) test/test_object_value_constructor_error.pas ...
grep -q "an object type cannot have a constructor" ...
```

from `d23f52948`. The `!` inverts a compiler that now correctly exits 0, so
the row fails and takes the tier with it. This watcher fired **six minutes
later**, at 16:06:33Z, which is the tightest corroboration of the cause
available and is what dated it.

Fixed in `9729073df`: the row and `test/test_object_value_constructor_error.pas`
removed, and the comment above the surviving rows corrected from "the three
things it deliberately refuses" to TWO, naming the commit that changed the
count so the next reader does not re-derive it. Coverage is not reduced —
`efe06a903` already carries both halves (`test_object_value_ctor.pas` asserts
the accepting shape byte-identically against fpc 3.2.2;
`test_object_value_ctor_fail.pas` asserts the four shapes still refused as
four separate compiles of one source).

**The range bound in this ticket is correct and was the thing that mattered.**
`cc03b4a51933` touches no buildable file, as the header says, and the cause is
below it — `efe06a903` is exactly one commit down.

**Worth keeping about the instrument, not about the bug:** the slug names
`test_object_value_type`, which passes, and the header warns about that in its
own words. The warning is right and it did not prevent the outcome — the
ticket sat 18 hours while the tier was red for every seat. A stub whose title
names a passing file reads as low-signal at a glance, which is the one thing a
regression stub cannot afford to read as. Not filed as a separate ticket:
`tools/twatch.py` already derives the title from `src:` deliberately, for
dedupe-key stability, and changing that is a Track T trade-off rather than a
defect.
- 2026-09-18 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 0a77fe3b8.
