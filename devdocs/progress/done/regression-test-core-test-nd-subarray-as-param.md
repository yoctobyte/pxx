---
prio: 70
track: P
status: done
---

> **Track guessed as P from the FAILING STEP** — line 3 of 6, `if command -v qemu-aarch64 >/dev/null 2>&1 && command -v qemu-arm >/dev/null 2>&1 \ && command -v qemu-riscv32 >/dev/nul`, which names `test/test_nd_subarray_as_param.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nd_subarray_as_param.pas at 0aff068c6d08 in step 3/6, `if command -v qemu-aarch64 >/dev/null 2>&1 && command -v qemu-arm >/dev/null 2>&1 \ && command -v qemu-riscv32 >/dev/nu…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T13:36:18Z
- **Test source:** test/test_nd_subarray_as_param.pas tools/expect_same.sh +2
- **Failing step:** line 3 of 6 of the job's recipe; it names `test/test_nd_subarray_as_param.pas`.
  ```
  if command -v qemu-aarch64 >/dev/null 2>&1 && command -v qemu-arm >/dev/null 2>&1 \ && command -v qemu-riscv32 >/dev/null 2>&1; then \ for arch in i386 aarch64 arm32 riscv32; do \ ./compiler/pascal26 --target=$arch test/test_nd_subarray_as_param.pas /tmp/test_ndsub_$arch >/dev/null; \ @# ...and the
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nd_subarray_as_param.pas'` at 0aff068c6d08caf3d9b2f8d4d5fd5886d27ac0c2

## Range
> **The named sha `0aff068c6d08` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0aff068c6d08`, last good `bb18f83c859e`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
sh: 17: Syntax error: ")" unexpected (expecting "done")
(tail)
ok: /tmp/testmgr-scratch-1824622/test_ndsub26  [code=73496B  data=4144B  bss=45356B  procs=143]
sh: 17: Syntax error: ")" unexpected (expecting "done")

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-06 — the seven watcher saw `test-core#src:test/test_nd_subarray_as_param.pas` GREEN at 803d79311d09 (tier native) and did NOT close this: the job's class is `qemu`, which testmgr treats as runtime-nondeterministic (RUN_RETRY_CLASSES) — a single pass does not refute a red there. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## Cause found and fixed — 2026-09-06 (frankB), `ca6b96843`

**Mine, and the watcher was right about everything including the part its own
banner disclaims.** The auto-filed track guess (P, from the failing step) is
correct, and so is the note that `0aff068c6d08` cannot be the cause: the real one
is `ebc0dcb4f`, widened by `ce5a257d9`, both several days of commits below the
tested sha.

I appended two Group 28 fixtures to `test-core` at an anchor that sits INSIDE the
qemu-user cross-target `for arch ... done` continuation. From `ebc0dcb4f` onward
the shell received my recipe comments and two `./$(COMPILER)` lines as the loop
body and the `done; ... else ... fi` tail as an orphan recipe line — hence
`sh: 17: Syntax error: ")" unexpected (expecting "done")`, which is an rc no test
in the harness can produce.

Fixed by closing the loop before those rows, six lines. Re-verified at HEAD:

```
tools/testmgr.py --tier native --job 'test-core#src:test/test_nd_subarray_as_param.pas'
  PASS  test-core#26  qemu  1.6s
```

**Why every gate I own was green while this sat on origin.** `--job src:<file>`
selects the recipe line for the file you NAME, so each of the five fixtures I
landed reported PASS while the loop they were pasted into could not parse.
`make compiler/pascal26` does not read this target, `--tier quick` does not run
`test-core`, and `gate.sh quick`'s Makefile arm checks that assertions can FAIL,
not that a recipe is valid sh. The instrument that sees it is the job BEFORE
yours — the neighbour you had no reason to run — and Track T's sweep, which is
what actually caught it. The generalisable half went to the logbook: after
appending to a Makefile recipe, run the neighbour job, not only your own.

The lint that would have caught it mechanically is filed separately by
frank-coordinator as
[[task-t-a-makefile-recipe-that-is-not-valid-sh-passes-every-gate]]; a naive
`sh -n` over logical recipe lines was attempted here and returns ~190 hits that
are almost all continuation-join artefacts, which is why it is a ticket and not
a gate row.
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
