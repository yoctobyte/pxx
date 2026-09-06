---
prio: 55
track: T
type: regression
status: done
owner: frankZ
blocked-by: [bug-t-tstate-fingerprints-the-code-and-the-hardware-but-not-the-emulator-toolchain]
summary: "RESOLVED 2026-09-06 by the owner's dist-upgrade of seven (route 2), not by a code change. seven now runs qemu-riscv32 10.2.1 (was 8.2.2) and the riscv32 `wait4-rusage rusage=UNTOUCHED` row is green there: tstate/seven.json records jobs[...]=pass and job_last_pass[...]=c543b335fb2f, seven's most recent run, with job_reason None. NOT A COMPILER BUG at any point — same compiler bytes on both boxes, kernel eliminated by tools/host_waitid_rusage_probe.c, cause was the emulator generation. Route 3 (a host-capability skip at ROW grain) must NOT be built: the condition is gone on both boxes and the assertion stays unweakened. Open residual, owned by nobody and no longer urgent: nobody has cited the qemu commit where TARGET_NR_waitid's rusage copy-back landed."
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

## Log
- 2026-09-05 — the seven watcher saw `test-core#src:test/c_crtl_wait.c` GREEN at 7867c5481c01 (tier native) and did NOT close this: the job's class is `qemu`, which testmgr treats as runtime-nondeterministic (RUN_RETRY_CLASSES) — a single pass does not refute a red there. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## Resolved 2026-09-06 by frankH — route 2 landed; route 3 must NOT be built

**seven's dist-upgrade removed the cause.** The box now reads
`qemu-riscv32 10.2.1`, kernel `7.0.0-31-generic`, gcc `15.2.0` — plexus's
generation, where this row was already deterministically green three runs deep.

**The evidence is a positive record, not an absence.** `tstate/seven.json`:

    jobs["test-core#src:test/c_crtl_wait.c"]          = "pass"
    job_last_pass["test-core#src:test/c_crtl_wait.c"] = c543b335fb2f
    job_reason["test-core#src:test/c_crtl_wait.c"]    = None

`c543b335fb2f` is seven's **most recent** run (2026-09-06T19:55:22Z). That
field is the one to quote rather than "it stopped appearing in the red lists":
`twatch.py:3494` writes it only for a job reporting literally `pass`, excludes
`skip` on purpose — *"a job that did not run cannot vouch for a sha"* — and
advances it only for jobs THIS run reported. So it says the job ran and passed,
which not-being-in-a-red-list does not. Corroborating and weaker: 263
native/full runs since the 09-05 green, 26h, zero mentions in any red list.

### What actually changed, and it was not the number of greens

The 2026-09-05 log entry below declined to close on one green because the job's
class is `qemu` (`RUN_RETRY_CLASSES`), where a single pass does not refute a
red. **That reasoning was right and still is.** What settles it is not a
greener sample — it is that the CAUSE went away and a field now records it.
The upgrade finished 17:30Z on 09-05; the green at 17:58:11Z was the FIRST run
of this job after it.

So the discriminator for a retry-class red is **"did the cause change"**, never
"how many greens have I now got". More samples from a changed instrument do not
answer the question the retry class raises; the toolchain fingerprint does.

**That fingerprint's first real use is CLOSING a red rather than explaining
one** — worth recording in
[[bug-t-tstate-fingerprints-the-code-and-the-hardware-but-not-the-emulator-toolchain]],
because the field was justified as a way to stop misreading environmental reds
as compiler bugs, and this is the other half of the same value: it is also how
you tell that an environmental red has genuinely ended.

### Route 3 is now the wrong thing to build

A row-grain host-capability skip would be machinery for a condition that no
longer exists on either box, and this ticket is explicit that the row must not
be weakened. The assertion stays exactly as it is. If the class recurs on a
future host, the fingerprint names it in the report header without anybody
needing a skip.

### The residual, unchanged and still owned by nobody

Nobody has cited the qemu commit where `TARGET_NR_waitid`'s rusage copy-back
landed. The elimination is now corroborated by an intervention — upgrade the
emulator, the row goes green — which is stronger than the original elimination
but still not the mechanism. It costs one search for anyone with network
access, and it is no longer urgent.
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit ce8567b28.
