---
prio: 70
track: A
status: done
owner: frankA
summary: "FIXED (see Log). EmitTerminateString read the string's LENGTH with EmitLoadVar -- the GENERIC variable load, which picks its width from TypeSlotSize -- so for a 1-byte-prefixed frozen string it loaded eight bytes: the length byte plus SEVEN CHARACTERS. rax = 0x6f6e2f747365741b at the fault (0x1b = 27 = Length(p) in the low byte, 'test/no' above it) and 'mov byte [rdi+rax], 0' wrote exabytes past the buffer. It crashed for a MISSING file too, because the NUL terminator runs before open() -- which is what made it read as an open()/read() defect. Re-laned T -> A: the auto-file's track was the fallback, not a finding. Second caller found by grep and also broken with no test on it at all: ir_codegen.inc's SysOpen arm through a ShortString path."
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 5 is `tools/expect_same.sh test_lfss26.1 "$(/tmp/test_lfss26 | tail -1)" "LOADFILE SHORTSTRING OK"`. The job's own `src` (`test/test_loadfile_shortstring.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_loadfile_shortstring.pas at 0aaaebfefaa8 in step 2/5, `tools/expect_same.sh test_lfss26.1 "$(/tmp/test_lfss26 | tail -1)" "LOADFILE SHORTSTRING OK"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T09:55:23Z
- **Test source:** test/test_loadfile_shortstring.pas tools/expect_same.sh
- **Failing step:** line 2 of 5 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_lfss26.1 "$(/tmp/test_lfss26 | tail -1)" "LOADFILE SHORTSTRING OK"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_loadfile_shortstring.pas'` at 0aaaebfefaa8bef502e819758c0aa93f835710b0

## Range
> **The named sha `0aaaebfefaa8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0aaaebfefaa8`, last good `9849f2d4c712`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-3494690/test_lfss26  [code=65304B  data=3104B  bss=44004B  procs=134]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_lfss26.1]
--- expected
+++ actual
@@ -1 +1 @@
-LOADFILE SHORTSTRING OK
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log

- 2026-09-04 - auto-filed by twatch at 0aaaebfefaa8, `track: T` as the documented
  FALLBACK for a failing step that named no owner.
- 2026-09-04 - re-laned to A, root-caused and resolved, commit PENDING-COMMIT.

## RESOLVED 2026-09-04 (frankA)

Reproduced at HEAD, and the PIN passed -- so a regression, not a standing gap,
and pin v403 is the wrong control for the fix because it predates whatever
introduced this. The control that works is HEAD with the change stashed: it
segfaults on both callers and passes every row above them.

**The fault named the cause.** Under gdb:

```
  => 0x40faed:  movb   $0x0,(%rdi,%rax,1)
     rax        0x6f6e2f747365741b
```

`0x1b` is 27, which is exactly the length of the path string, and the bytes
above it are `test/no`. So rax held the length byte AND seven characters: an
8-byte load of a 1-byte prefix.

`EmitTerminateString` called `EmitLoadVar(idx)` -- the GENERIC variable load,
which takes its width from `TypeSlotSize`. Its four siblings --
`EmitLoadStrLen`, `EmitStoreStrLen`, `EmitLeaStrDataRdi`, `EmitLeaStrDataRsi`
-- all follow the KIND, and the phase-1 audit that named them called them a
pair, then a trio, then a quartet, each correction finding one more. This was
the fifth and it was not in the set. Fixed by calling `EmitLoadStrLen` and
moving rcx to rax: three bytes, and one fact stated once rather than a sixth
place for the next layout change to miss.

**It crashed for a MISSING file too**, which is why the symptom pointed at
open()/read(). The NUL terminator is written before open() is called and does
not care whether the path exists.

**A second caller, found by grep and never tested at all.**
`ir_codegen.inc`'s SysOpen arm branches on the path symbol's kind and takes
the same emitter pair for anything that is not a `tyAnsiString` handle.
`test_cross_sysopen_family.pas` declares `path: AnsiString` and is therefore
entirely on the managed side, so the raw branch had no coverage -- the same
coverage hole `test_loadfile_shortstring.pas`'s own header describes for
LoadFile, one builtin along. Pre-fix HEAD segfaults on it;
`test/test_sysopen_shortstring_path.pas` now guards it, native only.

Native only because of a THIRD finding, measured while trying to wire it
cross: i386, aarch64 and arm32 refuse a ShortString SysOpen path by name,
while riscv32 and xtensa compile it and answer FALSE for a file that opens
fine one line earlier. Filed as
`bug-a-riscv32-and-xtensa-accept-a-shortstring-sysopen-path-and-open-nothing`.
