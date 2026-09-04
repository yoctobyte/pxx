---
prio: 70
track: T
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_rtti_reg26 "$(/tmp/test_rtti_reg26)" "$(printf 'Count: 3\nClass 0: TInterfacedObject\nClass 1:`. The job's own `src` (`test/test_rtti_reg.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_rtti_reg.pas at 6b08a2ae84f2 in step 2/2, `tools/expect_same.sh test_rtti_reg26 "$(/tmp/test_rtti_reg26)" "$(printf 'Count: 3\nClass 0: TInterfacedObject\nClass 1…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T15:56:12Z
- **Test source:** test/test_rtti_reg.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_rtti_reg26 "$(/tmp/test_rtti_reg26)" "$(printf 'Count: 3\nClass 0: TInterfacedObject\nClass 1: TBase\nClass 2: TChild')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_rtti_reg.pas'` at 6b08a2ae84f25d82d969d88c528f776847a93801

## Range
> **The named sha `6b08a2ae84f2` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `6b08a2ae84f2`, last good `3d68386f85e7`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2090791/test_rtti_reg26  [code=65304B  data=3648B  bss=43524B  procs=136]
expect_same: MISMATCH [test_rtti_reg26]
--- expected
+++ actual
@@ -1,4 +1,4 @@
 Count: 3
-Class 0: TInterfacedObject
-Class 1: TBase
-Class 2: TChild
+Class 0: TInterface
+Class 1: 
+Class 2: 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## A real regression, and the only one of the seven (frankA, 2026-09-04)

Six sibling tickets filed in the same run were a missing wasmtime on the test
host. **This one was not.** `test/test_rtti_reg.pas` had not been touched since
2026-06-20 and went red on a two-hour-old tree, which is the shape the other six
did not have.

### The mechanism, and it was predicted in writing a day earlier

RTTI names are **word**-length-prefixed blobs: `rtti_emit.inc` points `NamePtr`
at `Strs[].Offset`, and the interned-literal pool keeps its 8-byte NativeInt
prefix. The test read them through `TRttiStr = string[255]`.

`string[N]` for `N <= 255` became **tyShortString** — the FPC one-byte prefix —
in phase 4 of `feature-p-implement-the-real-tyshortstring-byte-prefix-layout`,
which landed 2026-09-04. So this declaration silently began claiming a byte
prefix over a word-prefixed blob. Measured here: `SizeOf(string[255])` is 256
and `SizeOf(string[256])` is 264.

`lib/rtl/typinfo.pas` was moved to `TRttiStr = string[256]` **ahead of** that
commit, for exactly this reason, and its comment predicts the symptom precisely:

> the blob prefix is written little-endian, so a byte-prefix reader takes byte 0
> — the LOW BYTE of the true length — and is CORRECT for every name under 256
> characters, while the chars it then reads at offset 1 are the prefix's own
> remaining zero bytes. Length right, name empty, no crash.

Observed: `Count: 3` correct, then `Class 0: \0\0\0\0\0\0\0TInterface` — seven NUL
bytes (the prefix's high bytes) followed by ten characters, seventeen in total,
which is `Length('TInterfacedObject')`. Exactly the predicted failure.

**The second copy was not moved with the first.** typinfo.pas got the migration
and this test kept its own duplicate declaration; nothing connects them, and no
instrument reports a type alias that has drifted from the one it was copied
from.

### Why it went red a DAY after the cause

`a50671107` (a pointer deref lost the shortstring kind on all seven targets)
made the deref honour the declared kind. Before it, the deref dropped the kind
and fell back to `tyString`'s 8-byte reading — **which is what this stale
declaration needed**. So the re-type broke the test and an unrelated correctness
fix removed the mask a day later, and the bisect points at the fix rather than
at the cause. The fix is right and stays.

### Fixed

`TRttiStr = string[256]`, matching the RTL, with the reason in the file. The
expected output is unchanged and the Makefile recipe is untouched.

**Plus the guard that would have caught this as itself**, because the cap above
is prose and prose is not a check:

```pascal
if SizeOf(TRttiStr) <> 264 then
begin
  writeln('TRttiStr is not the word-prefixed kind: SizeOf=', SizeOf(TRttiStr), ...);
  Halt(1);
end;
```

Positive control run: with the cap put back to 255 the guard fires, exits 1 and
prints `SizeOf=256 ... string[N<=255] is tyShortString and CANNOT read an RTTI
name` — instead of three silently mangled names. It costs one line of output on
failure and zero on success, so the expected text does not change.
