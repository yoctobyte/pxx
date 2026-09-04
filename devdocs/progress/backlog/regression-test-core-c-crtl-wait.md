---
prio: 70
track: C
---

> **Track guessed as C from the FAILING STEP** — line 5 of 5, `for a in i386 arm32 aarch64 riscv32; do \ case $a in i386) q=qemu-i386;; arm32) q=qemu-arm;; aarch64) q=qemu-aarch64;; r`, which names `test/c_crtl_wait.c`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-core#src:test/c_crtl_wait.c at 27303aeeb35c in step 5/5, `for a in i386 arm32 aarch64 riscv32; do \ case $a in i386) q=qemu-i386;; arm32) q=qemu-arm;; aarch64) q=qemu-aarch64;; …` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T17:00:14Z
- **Test source:** test/c_crtl_wait.c tools/expect_same.sh +1
- **Failing step:** line 5 of 5 of the job's recipe; it names `test/c_crtl_wait.c tools/expect_same.sh tools/run_target.sh`.
  ```
  for a in i386 arm32 aarch64 riscv32; do \ case $a in i386) q=qemu-i386;; arm32) q=qemu-arm;; aarch64) q=qemu-aarch64;; riscv32) q=qemu-riscv32;; esac; \ if [ "$a" = i386 ] || command -v $q >/dev/null 2>&1; then \ ./compiler/pascal26 --target=$a test/c_crtl_wait.c /tmp/c_wait26_$a >/dev/null || { ech
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/c_crtl_wait.c'` at 27303aeeb35cb77dd7b6ea2fccfafa3fbc2694fc

## Range
> **The named sha `27303aeeb35c` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `27303aeeb35c`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
ok: /tmp/testmgr-scratch-2535929/c_wait26  [code=352024B  data=16008B  bss=82516B  procs=913]
=== c_wait26: i386 OK ===
=== c_wait26: arm32 OK ===
=== c_wait26: aarch64 OK ===
expect_same: MISMATCH [riscv32/c_wait26]
--- expected
+++ actual
@@ -8,5 +8,5 @@
 after-cont       ret=ok   errno=0  exited=1 code=5 signalled=0 sig=-1 stopped=0 ssig=-1 cont=0
 wait             ret=ok   errno=0  exited=1 code=3 signalled=0 sig=-1 stopped=0 ssig=-1 cont=0
 wait4-rusage     ret=ok   errno=0  exited=1 code=9 signalled=0 sig=-1 stopped=0 ssig=-1 cont=0
-wait4-rusage     rusage=written
+wait4-rusage     rusage=UNTOUCHED
 notmychild       ret=minus1 errno=10 status=UNTOUCHED

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
