---
prio: 70
track: A
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `/tmp/cva_arg_pointer_pointee_b20126; tools/expect_same.sh cva_arg_pointer_pointee_b20126-rc "$?" "42"`. The job's own `src` (`test/cva_arg_pointer_pointee_b201.c`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cva_arg_pointer_pointee_b201.c at 6e622be95680 in step 2/2, `/tmp/cva_arg_pointer_pointee_b20126; tools/expect_same.s` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T08:27:47Z
- **Test source:** test/cva_arg_pointer_pointee_b201.c tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  /tmp/cva_arg_pointer_pointee_b20126; tools/expect_same.sh cva_arg_pointer_pointee_b20126-rc "$?" "42"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-core#src:test/cva_arg_pointer_pointee_b201.c'` at 6e622be956803d7e310994163d5f9e55db4eddc9

## Range
bad `6e622be95680`, last good `a96ef413f872`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1597241/cva_arg_pointer_pointee_b20126  [code=237336B  data=10408B  bss=63600B  procs=675]
expect_same: MISMATCH [cva_arg_pointer_pointee_b20126-rc]
--- expected
+++ actual
@@ -1 +1 @@
-42
+3

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## RE-LANED TO A, AND RESOLVED (2026-09-01, frankC)

Track A, not T. The auto-filed `track: T` is the documented fallback for a
failing step that names no owner, and the ticket says so itself; the defect is
in `EmitParamSpillsForTarget`'s SysV arm.

**The bisect was exact and the named commit is the cause** -- reproduced at
`6e622be95680` (exit 3, want 42) and confirmed green at its parent
`f39e158dd`, both built from a clean fixedpoint rather than inferred from the
range.

**Cause.** That commit moved the callee spill onto `ABISysVArgPlace` and
converted every reader of the bank counter `intIdx` to the oracle's `slotReg`.
One reader was left behind:

    if (intIdx = 0) or (intIdx = 1) then EmitB($40);   { REX for dil, sil }

The oracle advances `intIdx` past the current slot, so for a 1-byte parameter
arriving in rdi or rsi the prefix was dropped and `mov %sil, off(%rbp)`
assembled as `mov %dh, off(%rbp)` -- **the high byte of rdx, a different
register**. It assembles and runs. b201 reached it through crtl's `sscanf`,
which is why the two hand-written `va_arg` arms in the same file passed and
only the third assertion failed.

**Why it survived the conversion.** Every other `intIdx` reader was a branch
condition or a case selector; this one is a nested `if` inside the `sz = 1`
arm. The conversion was pattern-matched on syntactic position without that
being a conscious choice, and the single instance in a different position got
through. Nothing warns: `intIdx` is still a live variable that now means
something else.

**Why the inertness proof missed it.** That commit was landed on 15
byte-identical images across four targets plus six hand-picked scalar shapes
compiled against a kept pre-change binary. All of it real, all of it green, and
**not one subject passed a narrow argument in rdi or rsi**. The harness proved
the shapes it contained were unchanged and said nothing about the shape it
lacked. The guard was aimed at "did the comparison run" and not at "can the
corpus contain the defect".

**Fixed and pinned** in `747d3479f`, with `test/c_abi_narrow_reg_params.c`
wired into `test-core`. A pxx-only subject is a valid oracle here, unusually
for this ticket family: a wrong REGISTER is not a convention, so
self-consistency does not rescue it. The file carries a negative control that
keeps every narrow parameter in rdx/rcx/r8/r9 -- and the first version of that
control was not one, since `(long w, char a, ...)` put `a` in sil and failed
alongside the positive row. Both directions were asserted against a
deliberately re-broken compiler.
- 2026-09-01 — resolved, commit PENDING-COMMIT.
