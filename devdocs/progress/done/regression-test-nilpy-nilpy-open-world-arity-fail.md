---
prio: 70
track: N
status: done
---

> **Track guessed as N from the FAILING STEP** — line 1 of 11, `./compiler/pascal26 test/nilpy_open_world_arity_fail.npy /tmp/nilpy_ow_ar26 2>&1 \ | grep -q "takes at most 4 arguments"`, which names `test/nilpy_open_world_arity_fail.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This expectation records a REFUSAL** (a *_fail / {%FAIL} test). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/nilpy_open_world_arity_fail.npy at 95e7eb26e171 in step 1/11, `./compiler/pascal26 test/nilpy_open_world_arity_fail.npy /tmp/nilpy_ow_ar26 2>&1 \ | grep -q "takes at most 4 arguments…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-13T16:47:25Z
- **Test source:** test/nilpy_open_world_arity_fail.npy test/test_nilpy_package_imports.npy +1
- **Failing step:** line 1 of 11 of the job's recipe; it names `test/nilpy_open_world_arity_fail.npy`.
  ```
  ./compiler/pascal26 test/nilpy_open_world_arity_fail.npy /tmp/nilpy_ow_ar26 2>&1 \ | grep -q "takes at most 4 arguments" \ || { echo 'nilpy_open_world_arity_fail: FAIL - a fifth positional argument must be refused, not dropped'; exit 1; }
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/nilpy_open_world_arity_fail.npy'` at 95e7eb26e171d8452452d5f4b0856306456fff78

## Range
bad `95e7eb26e171`, last good `c21e1edc4598`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
nilpy_open_world_arity_fail: FAIL - a fifth positional argument must be refused, not dropped

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-09-13 — resolved, commit The row was asserting a CONSTANT CEILING and the ceiling moved. Not a regression:
`95e7eb26e` removed the four-argument cap on the run-time dispatched path (a
list-taking `pydyn_methl`), so the literal string the row grepped for --
`takes at most 4 arguments` -- can never be emitted again, and the bisect
converged correctly onto the commit that FIXED what the row was guarding. The
watcher's own note flags exactly this case and it was right.

Replaced rather than renumbered. The fixture's own comment says what it exists
for -- "dropping the fifth argument silently is how a call comes back with a
plausible wrong value" -- and a number in a grep does not serve that, so the row
now asserts the INVARIANT: five and seven positional arguments through the
run-time dispatched path arrive with the right VALUES, and a sixth-with-a-default
plus a star tail encode three facts in one integer, so the row cannot be
satisfied by a dropped argument, by a default filling a written slot, or by a
star swallowing one. True at a ceiling of 4, of 64 and of 80.
`test/test_nilpy_open_world_arity_is_not_truncated.npy` + `.expected`;
`test/nilpy_open_world_arity_fail.npy` is deleted.

A SECOND row keeps the refusal half, which is the part that must not be lost:
whatever the current ceiling is, exceeding it must REFUSE rather than truncate.
Its argument count is generated (65) and the assertion reads the number out of
the compiler's own message (`dispatched at run time` + `takes at most`) instead
of naming it, so raising MAX_DYN_ARGS keeps the row meaningful; the one thing to
change is the generated count, and the recipe says so.

Found while repairing this: a container result RETURNED out of a run-time
dispatched call comes back as a raw pointer
(bug-n-a-dynamically-dispatched-call-loses-its-return-kind-when-it-is-returned,
p65). The obvious spelling of the new row -- returning `[sum, f, len(rest)]` --
is red for that reason and not for an arity reason, which is why the row encodes
integers and says so inline..
