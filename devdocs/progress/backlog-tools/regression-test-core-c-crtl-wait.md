---
prio: 55
track: T
type: regression
status: backlog
owner: frankZ
blocked-by: [bug-t-tstate-fingerprints-the-code-and-the-hardware-but-not-the-emulator-toolchain]
summary: "NOT A COMPILER BUG, and re-laned from C to T. riscv32's `wait4-rusage rusage=UNTOUCHED` is red on seven and deterministically green on plexus from BYTE-IDENTICAL compiler bytes (compiler_sha256 fcc5ad9a29a61c10c... both boxes) with an EMPTY `git diff` outside devdocs/. seven runs qemu-riscv32 8.2.2 where plexus runs 10.2.1; the host kernel is eliminated on seven's own box by tools/host_waitid_rusage_probe.c, which prints rusage=written there with its arg5-NULL control printing UNTOUCHED. The target-side path is four pure pass-throughs and the same riscv32 binary writes rusage under a newer emulator. Fixing it needs root on seven (owner) or a host-capability skip at ROW grain (T) — do NOT weaken the assertion."
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

## Diagnosed 2026-09-04 by frankZ — the tree is exonerated, the emulator is not

**Re-laned C -> T.** The `track: C` above was twatch guessing from the failing
step, which is a documented FALLBACK and not a finding; the step names a C
source because the test is written in C, which says nothing about what broke.

**What was measured.** Full detail, both boxes' version strings verbatim and
the probe's decision table, live in
[[bug-t-tstate-fingerprints-the-code-and-the-hardware-but-not-the-emulator-toolchain]].
In short:

- seven's report records `compiler_sha256: fcc5ad9a29a61c10c...`; the local
  build at `162a22dd3` is byte-identical, `converged after 1 round(s)`.
- `git diff --name-only b040c90e6c8b 162a22dd3` outside `devdocs/` is EMPTY.
- Deterministically green on plexus, three runs through
  `tools/run_target.sh riscv32`; consistently red on seven across three shas.
- Same compiler bytes, same sources, opposite answers -> the host.
- seven `qemu-riscv32 8.2.2` / kernel `6.8.0-138`; plexus `10.2.1` / `7.0.0-30`.
  Two variables, so the version delta alone does not discriminate.
- `tools/host_waitid_rusage_probe.c` removes qemu from the path and asks the
  kernel alone. Both kernels print `rusage=written`; the arg5-NULL positive
  control prints `UNTOUCHED` on both. **The kernel is eliminated on seven's own
  box, in the same run.**
- The target-side path is enumerated, not assumed: `wait4()` ->
  `__pxx_wait4` -> `PalWait4` -> `PalBackendWait4` ->
  `__pxxrawsyscall(SYS_waitid, ..., Int64(rusage), 0)`. No NULL substitution;
  `waitpid` is the arm that deliberately passes 0. And the same riscv32 binary
  DOES write rusage on plexus, so arg5 reaches the kernel from riscv32 codegen.

**Honest scope: this is an elimination, not a demonstration.** The emulator is
what is left standing on an enumerated path. Nobody has cited the qemu commit
where `TARGET_NR_waitid`'s rusage copy-back landed; that citation is the one
open residual and it needs network access this session did not spend.

**Do not weaken the row.** The waitid rebuild is the most bespoke code on that
path and this is the only row that exercises its rusage argument. An assertion
that accepts either answer is worth less than a red that says why. The routes
are: fingerprint the toolchain (T, the umbrella ticket), upgrade seven's
emulators (root on seven -> **the owner**), or skip it as a host capability the
way `test-core#1058` is skipped for RDRAND — noting that RDRAND skips a JOB and
this is one ROW inside one, which is the part wanting T's judgement.
