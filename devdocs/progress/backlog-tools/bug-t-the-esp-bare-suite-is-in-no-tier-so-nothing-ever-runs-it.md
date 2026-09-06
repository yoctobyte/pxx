---
slug: bug-t-the-esp-bare-suite-is-in-no-tier-so-nothing-ever-runs-it
track: T+S
prio: 45
type: bug
blocked-by: []
status: backlog
found: 2026-08-30
found-by: frankS
summary: "THREE ESP suites, not two: test-esp-bare, test-esp-softfloat AND test-esp-idf appear in ZERO testmgr tiers and in no script -- only test-xtensa is enrolled. Re-verified 2026-09-05, and the suite was then EXECUTED for the first time: it immediately caught bug-a-no-program-declaring-a-class-can-build-for-esp-profile-bare, a profile-wide compiler defect present indefinitely. The assertion count in the original body is WRONG (see the 2026-09-05 note): 27 sites in test-esp-bare and 2 in test-esp-softfloat, and on a box WITH the Espressif qemu builds NONE of them skip -- so the '92% skip, maybe split the 2 hosted rows out' advice is a property of the measuring box, not of the target. Post-fix clean run: rc=0, 26 distinct assertions all ok, 0 skipped. Enrolment is still Track T's, in tools/testmgr.py, untouched here. 2026-09-06: test-esp-idf added to this ticket -- it ran ONE of the nine examples/esp32 projects (timer-c3, for both chips), so gpio-c3, net-c3, dns-c3 and fs-c3 were executed by nothing at all and all four PASS; wired into the target this session, enrolment still open."
---

# The ESP bare-metal suite is enrolled nowhere

Measured, `grep -rn 'test-esp-bare' --include='*.py' --include='*.sh'`:

| | |
| --- | --- |
| xtensa/esp jobs in `tools/testmgr.py` | **1** — `test-xtensa`, in `full` |
| tiers containing `test-esp-bare` | **0** |
| tiers containing `test-esp-softfloat` | **0** |
| references in `tools/gate.sh` or any script | **0** |

Both targets are declared `.PHONY` in the Makefile and are reachable only by
typing them.

## How it was found, which is the part worth keeping

Not by auditing the tier list. `bug-a-the-xtensa-windowed-abi-is-compiled-twice-and-executed-never`
said the windowed ABI was never executed; by the time that ticket was worked,
frank-optimize-b4 had already added the executed windowed canary — **into
`test-esp-bare`**. So the row existed, was correct, used the right two outcome
slots, and still could not fail anything, because nothing runs the target it
sits in.

**That is the same defect one level up.** The ticket's own sentence was *"a suite
whose PASS and whose SKIP print the same thing"*; this is a row whose pass and
whose non-execution print the same thing, which is nothing. Fixing coverage by
adding a correct row to an unenrolled target moves the invisibility rather than
removing it — and it is invisible in exactly the way the first one was, because
a Makefile target looks gated when you are reading the Makefile.

The windowed canaries now live in `test-xtensa` (enrolled, `full`) for this
reason. b4's row in `test-esp-bare` is a harmless duplicate of one of them and
is b4's to keep or drop.

## What enrolment would actually buy, measured rather than assumed

`test-esp-bare`'s recipe is 200 lines with **26 assertions**, and **24 of those
sit behind `not installed` guards** that skip when the Espressif qemu builds are
absent. Only **2** use `tools/run_target.sh` unconditionally.

So on a box without `~/.espressif`, enrolling this target gates 2 real rows and
prints 24 skips — worth doing, but do NOT enrol it and read the resulting green
as "ESP is covered". That is the same misreading `test-xtensa`'s own header
already warns about (*"55/142, not GREEN"*), and the honest form is the same:
name the skipped population in the job's comment.

The prior question is whether the watcher box has the Espressif toolchains at
all. If it does not, the useful move may be to split the 2 unconditional hosted
rows out into an enrolled target and leave the 24 hardware-dependent ones where
they are, rather than enrolling a target that is 92% skip.

## Track letter

**T+S.** The enrolment lives in `tools/testmgr.py`, which is Track T's file, so
this is filed rather than fixed — T owns the tool. The *reason to care* is Track
S's: ESP is S's campaign and this is S's suite going unrun. The Makefile side of
any split would be S's to write.

## 2026-09-05 (frankS) — the suite was RUN, and the assertion count above is wrong

**The enrolment claim still holds**, re-verified: `test-esp-bare` and
`test-esp-softfloat` appear in zero testmgr tiers and no script; only
`test-xtensa` is enrolled (`tools/testmgr.py:249`).

**The assertion count does not hold, and the design advice built on it does
not either.** This ticket says *"26 assertions, 24 of those behind `not
installed` guards, only 2 unconditional"*, and recommends possibly splitting
the 2 hosted rows out rather than enrolling a target that is *"92% skip"*.

That count was taken on a box **without** `~/.espressif`. Corrected, by
bounding each recipe at the next target rather than by a line range:

| | assertion sites |
| --- | --- |
| `test-esp-bare` (25955–26168) | **27** — 25 guarded `diff … exit 1`, plus 2 `expect_same` |
| `test-esp-softfloat` (26169–26186) | **2** |
| total | **29** |

**On a box WITH the Espressif qemu builds, none of them skip.** So the "92%
skip" figure is a property of the measuring box, not of the target, and
splitting out "the 2 unconditional rows" would solve a problem such a box does
not have. The honest form of the recommendation is: **enrolment value depends
on whether the runner has `~/.espressif`, and that is a fact about the runner,
not about the suite.**

*(An intermediate count of "24 in test-esp-softfloat", relayed by this author
earlier the same evening, was wrong: the line range used ran past the target's
end into `qemu-env-check`. The number above is bounded at the next target and
is the one to use.)*

## It was executed for the first time, and it caught a real defect immediately

`PXX_ALLOW_FULL_SUITE=1 make -k test-esp-bare test-esp-softfloat` on plexus
(both Espressif qemu builds present, `esp_develop_9.2.2_20250817`).

**First run, compiler `fe1e9c37d322`:** 1 MISMATCH — `esp32c3 exception`,
oracle 12 lines, device output empty. That was **not** a device fault and not
chip-specific; it was
`bug-a-no-program-declaring-a-class-can-build-for-esp-profile-bare` —
**no program declaring a `class` could build for `--esp-profile=bare` at all,
on either chip.** A five-line program reproduces it.

**After that fix, clean run:** `rc=0`, **26 distinct assertion outcomes all ok**
(28 lines; the 2 softfloat rows execute under both targets), **0 MISMATCH,
0 skipped, 0 build failures.**

So the answer to *"what would enrolment actually buy"* is now measured rather
than estimated: on a box with the toolchains it buys 26 real cross-checked
assertions against the x86-64 oracle, and the first time anyone ran them they
found a profile-wide compiler defect that had been present indefinitely.

**Method note, since this ticket is about invisibility.** Two runs during this
work were **discarded** because `tools/esp_run_bare.sh` was edited while they
were executing — `/bin/sh` reads a script incrementally. Established by
timestamps (script 20:22:43; both logs still being written at 20:22:47 and
20:22:48), not by feel. The tell was a row count no clean run produces (`ok=3`
where the clean run had 16). The defect above does not rest on either discarded
run: it was confirmed by a by-hand compile, a five-line repro on both chips, and
the same program building under `--platform=posix`.

**Still Track T's to enrol** — `tools/testmgr.py` is T's file and this seat has
not touched it. What changed is that the enrolment question now has a measured
answer behind it instead of an estimate.

## Enrolment BLOCKS a guard that wants to live here (frankS, 2026-09-05)

`bug-a-the-esp32-bare-image-doubled-in-code-and-grew-half-again-in-bss` wants a
size row, and `test-esp-bare` is its natural home. **I did not add one, and the
reason is an ordering constraint T should have when it decides this ticket.**

A size row written into a target that is in zero tiers would be **exactly as
unwatched as the number it guards.** The ticket's complaint is "nothing watches
this number"; adding an unenrolled row answers it on paper and changes nothing.

That is not hypothetical here — it is this suite's own history repeating. The
windowed-ABI canary was added to `test-esp-bare` and could not fail anything,
which is what produced this ticket. Adding a size row now would be the **third**
layer of the same defect, after the unenrolled target and the rows shadowed
behind an earlier `exit 1`.

**So the dependency runs enrolment → guard, not guard → enrolment.** Anyone who
files a "add a size row" ticket should have it `blocked-by` this one.

## 2026-09-06 (frankF) — the number Track T asked for: 29 assertions, both chips, ZERO skips

Ran on plexus, `PXX_ALLOW_FULL_SUITE=1 make -k test-esp-bare test-esp-softfloat`
at `d6de711d1`, `compiler/pascal26 = c9de36a3754e`, `converged after 1 round(s)`.
`rc=0`, read off the command's own exit status and not off the background
wrapper's.

**29 `ok` rows, 0 MISMATCH, 0 skipped, 0 build failures.** Both chips on every
row that has two: bare-boot, softfloat kernels, atomics (S32C1I and the riscv
pair), Call0 large frames via ADDMI, inline asm plus the windowed lowering,
odd-index 64-bit argument pairs, frozen `string[N]`, var→var forwarding, record
copy and by-value results, try/except/finally, class + virtual dispatch,
proc-var indirect calls, >6-word arguments, and softfloat/int64. Every one is a
UART-output diff against the x86-64 oracle, executed under the Espressif qemu
builds (`esp_develop_9.2.2_20250817`), not a build check.

Wall time ~12 minutes, derived from the job's launch and its output file's mtime
(21:04:58 +0200) rather than from a timer — treat it as an order of magnitude,
and re-time it under `time` before sizing a tier slot on it.

**So the enrolment question now has both halves measured.** frankS established
what it buys on a box with the toolchains; this establishes that at HEAD, today,
it is entirely GREEN — a tier gains 29 executed cross-checks and no new red.
That is the cheap case for enrolling and the one that expires: it is true of
`d6de711d1` and of nothing else.

**The framing that belongs with the number, and it is not mine — frankZ's, via
the coordinator.** *A false skip is worse than a false red: a red is loud, a
skip is silent.* **A job in zero tiers is not even a skip.** `test-esp-bare` and
`test-esp-softfloat` appear in no tier as a red, as a skip, or as a hole — they
appear as nothing, so no count reports them and there is nothing to scrutinise.
Under a release that advertises "all frontends and all targets", enrolment is
what turns that absence into a row that can be read. This is also why
`skip_holes == 0` cannot speak for these two: they are not skipped for a reason
the harness owns, because the harness has never been told they exist.

**What I did NOT do, deliberately.** I did not touch `tools/testmgr.py`. It is
T's file, frankB is in it on the un-skips, and a number lands cleanly where an
edit would collide. Whether seven has `~/.espressif` is still the open half and
is a fact about the runner, not about the suite — I can only report that plexus
does.

**One thing enrolment would immediately expose, filed today:**
[[bug-a-assert-is-undefined-on-the-esp-bare-profile]] — no program containing an
`Assert` can be built for `--esp-profile=bare` on either chip. Twenty-nine green
rows did not see it because `test_esp_bare.pas` contains no assertion. That is
this ticket's own thesis holding for a second time: the suite is not merely
unwatched, it is unwatched in a way that makes its green misleading about the
target's coverage rather than about its correctness.

### The open half, answered by measurement rather than by asking: seven cannot run these rows today

frankS left this as *"a fact about the runner, not about the suite"* and it was
still open. It is answerable without touching seven, because the blocker is not
whether a box has *a* qemu — it is that **stock QEMU has no ESP32 machine at
all**, on either ISA. Measured on plexus, which has both builds side by side:

| emulator | version | ESP machines |
| --- | --- | --- |
| `/usr/bin/qemu-system-xtensa` | 10.2.1 (Debian/Ubuntu) | **none** — kc705, lx60/lx200, ml605, sim, virt |
| `/usr/bin/qemu-system-riscv32` | 10.2.1 | **none** |
| Espressif `qemu-system-xtensa` | esp_develop_9.2.2_20250817 | `esp32`, `esp32s3` |
| Espressif `qemu-system-riscv32` | esp_develop_9.2.2_20250817 | `esp32c3` |

So the recipe's `$HOME/.espressif/tools/qemu-*/...` guard is **correct and not
over-narrow**. A box with a newer stock qemu is not a substitute, and enrolling
on such a box would produce 29 rows of `not installed` — a false skip in exactly
frankZ's sense, where the silent answer is worse than a red.

**What that makes the enrolment decision.** It is not a `tools/testmgr.py` edit
waiting on someone to make it. It is: install the Espressif toolchain on seven
(an infra act), THEN enrol. Enrolling first buys a target that prints skips.

### And the archive cannot tell you this, which is the reusable part

`twatch.py`'s `RUNNER_BINARIES` (tools/twatch.py:7003) records `qemu-xtensa` and
`qemu-riscv32` — the **user-mode** binaries `tools/run_target.sh` resolves from
PATH. seven's stamp says `qemu-xtensa: 10.2.1`, `qemu-riscv32: 10.2.1`, and both
are true. Neither is the emulator these rows need: `qemu-system-xtensa` from
`~/.espressif` is a different binary, from a different fork, with a capability
the recorded one does not have.

**A reader who checks the archive for "does seven have qemu-xtensa" gets YES and
is wrong about this question.** The field does not error and does not lie — it
answers about the user-mode runner. That is the same shape as the incident the
fingerprint's own docstring was written for (*"a cross-target verdict is also a
statement about an EMULATOR, which nothing recorded"*), one fork further in.

Not fixed here — `twatch.py` is Track T's file and frankB is in it. If T wants
it, the ESP system emulators are a two-entry addition to `RUNNER_BINARIES`
resolved at the Espressif path rather than on PATH, and they would make this
ticket's open half readable from the archive instead of by measurement.


## 2026-09-06 (frank-coord-front) — there is a THIRD ESP suite, and it was worse

`test-esp-idf` belongs in this ticket's table and was never in it. It is the
FreeRTOS/lwIP route — an IDF project, real sockets, real DNS — and it is the
route the owner calls the more interesting one, so its absence costs more than
the bare suite's.

| | tiers | scripts | in `.PHONY` list at Makefile:160 |
| --- | --- | --- | --- |
| `test-esp-bare` | 0 | 0 | yes |
| `test-esp-softfloat` | 0 | 0 | yes |
| **`test-esp-idf`** | **0** | **0** | **no — its own line, 137** |

Same enrolment gap, one worse detail: it is not even in the shared `.PHONY`
block, so a reader scanning that line for the ESP suites finds two of three.

### What the target actually ran, which is the finding

`examples/esp32/` holds **nine** projects. Before today, `test-esp-idf` compiled
exactly **one source** — `timer-c3/main/main.pas` — and it compiled that same
source for BOTH chips in its `for chip in esp32c3 esp32s3` loop. So:

- `gpio-c3`, `net-c3`, `dns-c3`, `fs-c3` were executed by **nothing at all** —
  no Makefile target, no script, no tier.
- `timer-s3/` was executed by nothing either. The s3 row does exercise xtensa
  codegen, but it does it from `timer-c3`'s file; `diff` of the two sources is
  **one line, the program name**, so nothing was lost — and nothing was gained
  by shipping the directory.
- `hello-c3`/`hello-s2`/`hello-s3` are `esp_run.sh`'s host project, so they are
  built constantly as scaffolding and asserted never.

**All four unwatched examples PASS.** That is the point rather than a relief:
this is working functionality nobody was watching, and an absence no count
reports is worse than a red — a red at least prints.

Wired in this session (Makefile `test-esp-idf`): gpio-c3, net-c3 and dns-c3
through `esp_run.sh`, fs-c3 through its own `build.sh qemu-assert`.

### Two instrument notes the next author needs

**Assert the SMOKE LINE, not the whole output.** `net-c3` prints an EPHEMERAL
peer port (`peer-port=64169` on one run) and `gpio-c3`'s pin reads differ
between qemu and silicon *by design* — its own verdict string is
`qemu-delivers-NO-gpio-edges`. A full-output diff would make both rows flap for
reasons that are not defects, and a flapping row gets deleted.

**`fs-c3` cannot go through `esp_run.sh`, and neither one is at fault.**
`esp_run.sh` builds every program inside the `hello-c3`/`hello-s3` project;
fs-c3 ships its own `partitions.csv` (a `storage` FAT partition) and an
`sdkconfig.defaults` selecting it. Routed through the stock table it fails with
`undefined reference to esp_vfs_fat_spiflash_mount_rw_wl` — **a symbol that IS
present in ESP-IDF v6.0.1**, so the two obvious readings (an API removal; a pxx
defect) are both wrong. Run its own `build.sh qemu-assert` and branch on that
rc. Its verdict: `OK fs-c3 -- ESP PAL file I/O works on target`.

Enrolment itself is still Track T's and still open — for three targets now.
