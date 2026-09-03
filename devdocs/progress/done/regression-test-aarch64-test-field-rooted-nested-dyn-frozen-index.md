---
prio: 70
track: A
status: done
---

> **Track A from the job NAME `test-aarch64`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_field_rooted_nested_dyn_frozen_index.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-aarch64#src:test/test_field_rooted_nested_dyn_frozen_index.pas@1 at 91b4b77ec631 in step 2/2, `tools/expect_same.sh aarch64/fieldrooted_nested_frozen_default "$(tools/run_target.sh aarch64 /tmp/test_aarch64_fieldro…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-03T17:03:39Z
- **Test source:** test/test_field_rooted_nested_dyn_frozen_index.pas tools/expect_same.sh +2
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh tools/run_target.sh test/test_field_rooted_nested_dyn_frozen_index.expected`.
  ```
  tools/expect_same.sh aarch64/fieldrooted_nested_frozen_default "$(tools/run_target.sh aarch64 /tmp/test_aarch64_fieldrooted_frozen_d)" "$(cat test/test_field_rooted_nested_dyn_frozen_index.expected)"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_field_rooted_nested_dyn_frozen_index.pas@1'` at 91b4b77ec631e4027893233277450f576e3008fc

## Range
> **The named sha `91b4b77ec631` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `91b4b77ec631`, last good `5e2dcc37c253`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
qemu: uncaught target signal 11 (Segmentation fault) - core dumped
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-1650242/test_aarch64_fieldrooted_frozen_d  [code=196376B  data=3472B  bss=42356B  procs=134]
qemu: uncaught target signal 11 (Segmentation fault) - core dumped
Segmentation fault (core dumped)
expect_same: MISMATCH [aarch64/fieldrooted_nested_frozen_default]
--- expected
+++ actual
@@ -1,5 +1 @@
-VAR   <var0><var1>
-FIELD <fld0><fld1>
-LEN   2 1
-ANSI  <ansi0><ansi1>
-INT   41 42
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Fixed by `f199ca260`, re-verified at HEAD (frankA, 2026-09-03)

Same defect as the three `test-core` rows closed against that commit, one
target over. It was mine: `0dedfb86c`'s SetLength classifier asked "is the
element a frozen string" of an `AN_INDEX` target, and one index into a DEPTH-2
dynamic array yields a depth-1 ARRAY whose `ASTTk` reports the ELEMENT's kind —
so `SetLength(r.matrix[0], 1)` on `array of array of string[10]` was routed to
the frozen-string arm, which wrote a length prefix over the sub-array's handle.
`NodeDynDepth` is now asked first.

Nothing aarch64-specific: the fix is in `pasparser_stmt.inc`, above codegen.
Re-verified anyway rather than inferred from the native green, because a
target-scoped claim needs the targets it did not fix. **The job's own
assertion**, `expect_same` against
`test_field_rooted_nested_dyn_frozen_index.expected`, run on every cross target
in BOTH prefix modes:

| target | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| x86-64 | OK | OK |
| i386 | OK | OK |
| aarch64 | OK | OK |
| arm32 | OK | OK |
| riscv32 | OK | OK |

The header's re-lane note is right and needs no action: Track A is correct, and
it is correct for the reason the note gives — the lane comes from the fix being
in the compiler, not from the job name.
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
