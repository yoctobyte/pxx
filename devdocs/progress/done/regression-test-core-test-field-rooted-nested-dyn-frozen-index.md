---
prio: 70
track: A
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh sweep_fieldrooted_frozen_default "$(/tmp/sweep_fieldrooted_frozen_d)" "$(cat test/test_field_rooted`. The job's own `src` (`test/test_field_rooted_nested_dyn_frozen_index.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_field_rooted_nested_dyn_frozen_index.pas@1 at 91b4b77ec631 in step 2/2, `tools/expect_same.sh sweep_fieldrooted_frozen_default "$(/tmp/sweep_fieldrooted_frozen_d)" "$(cat test/test_field_roote…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-03T16:51:44Z
- **Test source:** test/test_field_rooted_nested_dyn_frozen_index.pas tools/expect_same.sh +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh test/test_field_rooted_nested_dyn_frozen_index.expected`.
  ```
  tools/expect_same.sh sweep_fieldrooted_frozen_default "$(/tmp/sweep_fieldrooted_frozen_d)" "$(cat test/test_field_rooted_nested_dyn_frozen_index.expected)"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_field_rooted_nested_dyn_frozen_index.pas@1'` at 91b4b77ec631e4027893233277450f576e3008fc

## Range
> **The named sha `91b4b77ec631` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `91b4b77ec631`, last good `5e2dcc37c253`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-1627775/sweep_fieldrooted_frozen_d  [code=69400B  data=3544B  bss=43524B  procs=134]
Segmentation fault (core dumped)
expect_same: MISMATCH [sweep_fieldrooted_frozen_default]
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

> **RE-LANED T/P -> A by the coordinator, 2026-09-03, on COMMIT CONTENT, not on the failing step.** The only code commit between the last GREEN native (`5e2dcc37c253`) and this RED (`91b4b77ec631`) is `0dedfb86c` "fix(A): SetLength through a field, an element or a deref", which touches `Makefile`, `compiler/ir_codegen.inc` and the 386/aarch64/arm32/riscv32/xtensa arms plus `compiler/pasparser_stmt.inc`. The other five commits in the window touch no code at all. That is a suspect established by ref arithmetic with zero builds — it is NOT a measured cause, and the author (franka-29) has been told and may reject it.

> **This may not be a regression.** The alias-cast row fails on a REFUSAL grep (`SetLength expects a`), and `0dedfb86c` deliberately widened what `SetLength` accepts. A refusal test going red is exactly what an intended widening looks like; if that is what happened, the TEST is what needs updating and there is no defect here. Establish which before treating any of these three as a bug.
- 2026-09-03 — resolved, commit f199ca260.
