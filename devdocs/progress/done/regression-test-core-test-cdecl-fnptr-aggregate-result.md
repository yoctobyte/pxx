---
prio: 70
track: P
status: done
---

> **Track guessed as P from the FAILING STEP** — line 3 of 17, `for t in i386 riscv32 aarch64 arm32; do \ case $t in i386) q=qemu-i386;; riscv32) q=qemu-riscv32;; aarch64) q=qemu-aarch`, which names `test/test_cdecl_fnptr_aggregate_result.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 5 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_cdecl_fnptr_aggregate_result.pas at b1f2b7d8812d in step 3/17, `for t in i386 riscv32 aarch64 arm32; do \ case $t in i386) q=qemu-i386;; riscv32) q=qemu-riscv32;; aarch64) q=qemu-aarc…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-28T06:12:23Z
- **Test source:** test/test_cdecl_fnptr_aggregate_result.pas tools/expect_same.sh +3
- **Failing step:** line 3 of 17 of the job's recipe; it names `test/test_cdecl_fnptr_aggregate_result.pas tools/expect_same.sh tools/run_target.sh test/test_cdecl_fnptr_aggregate_result.expected`.
  ```
  for t in i386 riscv32 aarch64 arm32; do \ case $t in i386) q=qemu-i386;; riscv32) q=qemu-riscv32;; aarch64) q=qemu-aarch64;; arm32) q=qemu-arm;; esac; \ if ! command -v $q >/dev/null 2>&1; then echo " pcdecl: $q absent, $t NOT verified"; continue; fi; \ ./compiler/pascal26 --target=$t --platform=pos
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_cdecl_fnptr_aggregate_result.pas'` at b1f2b7d8812dce14468da84ec8e1e0e867f3c412

## Range
> **The named sha `b1f2b7d8812d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b1f2b7d8812d`, last good `9a245b91c409`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-426107/pcdecl26  [code=23192B  data=4624B  bss=35512B  procs=163  codeseg=24288B]
pcdecl riscv32 compile FAIL

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-28 — the borg watcher saw `test-core#src:test/test_cdecl_fnptr_aggregate_result.pas` GREEN at a8e99254ed4b (tier native) and did NOT close this: the job's class is `qemu`, which testmgr treats as runtime-nondeterministic (RUN_RETRY_CLASSES) — a single pass does not refute a red there. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-28 — frankD re-ran the failing step with the compiler whose sha256 is `0ded1e5d04c8` (built from master after the fix; the fix is on master): compiling `test/test_cdecl_fnptr_aggregate_result.pas` for i386, riscv32, aarch64 and arm32 (step 3) exits 0 with no error on all four. The failure was a compile-time refusal or a deterministic crash, so one run settles it; closed in the coordinator's sweep of tickets fixed on 2026-09-28.
- 2026-09-28 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
