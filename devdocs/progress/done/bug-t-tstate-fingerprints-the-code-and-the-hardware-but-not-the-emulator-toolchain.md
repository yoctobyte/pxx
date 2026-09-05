---
track: T
prio: 70
type: bug
status: done
found: 2026-09-04
found-by: frankZ
owner: frankZ
blocked-by: []
summary: "seven is the box that does the sweeping and its whole emulator toolchain is a Debian generation behind the box every lane develops on: qemu-riscv32/arm/xtensa/i386 all 8.2.2 against plexus's 10.2.1, kernel 6.8.0-138 against 7.0.0-30, gcc 13.3.0 against 15.2. tstate records `code_fp` and `hw_fp` and NO toolchain fingerprint, so a cross-target red caused by the emulator is indistinguishable from a compiler bug and there is no field a reader can check. First instance measured and isolated: test-core#src:test/c_crtl_wait.c's riscv32 rusage row, red on seven and green on plexus from byte-identical compiler bytes. The class will fire again and will look like a compiler bug every time."
---

# tstate fingerprints the code and the hardware, but not the emulator toolchain

## The measurement

| | seven (sweeps) | plexus (development) |
| --- | --- | --- |
| `qemu-riscv32` | **8.2.2** (Debian 1:8.2.2+ds-0ubuntu1.18) | **10.2.1** (Debian 1:10.2.1+ds-1ubuntu3.2) |
| `qemu-arm`, `qemu-xtensa`, `qemu-i386` | 8.2.2, uniformly | 10.2.1 |
| kernel | 6.8.0-138-generic | 7.0.0-30-generic |
| gcc | 13.3.0 | 15.2 |

Version strings verbatim, read on both boxes with the same command on
2026-09-04 (frankuser, over ssh). It is not a riscv32-specific install — the
whole emulator toolchain on the sweeping box is one Debian generation behind.

`devdocs/progress/tstate/seven.json` carries `code_fp` (the tree) and `hw_fp`
(the hardware) and **nothing about the toolchain**. `tools/twatch.py` has one
`hw_fp` call site and no qemu, gcc or kernel capture at all.

## Why that is a defect and not a curiosity

Every cross-target verdict in the archive is measured on a 2024-vintage
emulator, while every local check any lane runs is measured on a 2025 one. So
**"cross-target red on seven, green locally" now has a standing environmental
explanation, and no field in the archive can distinguish it from a compiler
bug.** A reader who diffs the tree finds nothing, checks `code_fp`, finds it
equal, and concludes the compiler. That is the wrong conclusion and the
instrument offers no way to reach the right one.

This is the same family as `bug-t-run-target-sh-s-exit-code-is-discarded-at-1082-call-sites`,
which produced seven auto-filed regressions on 2026-09-04 all accusing the
compiler and all caused by wasmtime not being installed. There the missing
binary was invisible; here the *version* of a present binary is invisible.

## The first instance, isolated

`test-core#src:test/c_crtl_wait.c`, row 8: `wait4-rusage rusage=UNTOUCHED` on
seven against an expected `written`. riscv32 only; i386, arm32 and aarch64 pass.

- seven's report records `compiler_sha256: fcc5ad9a29a61c10c...`; the local
  build at `162a22dd3` is byte-identical, `converged after 1 round(s)`.
- `git diff --name-only b040c90e6c8b 162a22dd3` outside `devdocs/` is **empty**.
- The row is deterministically **green on plexus**, three runs through
  `tools/run_target.sh riscv32`.

Same compiler bytes, same sources, opposite answers — so the cause is the host.
riscv32 is the one target with no `wait4`, so it reaches the kernel through
`SYS_waitid` with the rusage pointer in arg5, and both the emulator and the
kernel sit on that path.

**The kernel is eliminated, on seven's own box, in the same run.**
`tools/host_waitid_rusage_probe.c` removes qemu from the path entirely — x86-64
native, glibc, raw `syscall(SYS_waitid, P_PID, pid, &si, WEXITED, &ru)`, same
0x5a sentinel and byte scan as the test's row 8 — and carries a positive
control (the identical call with **arg5 NULL**, which nothing may write),
because a `written` answer with no control is unfalsifiable:

    seven : waitid rc=0 si_pid=3085262 si_status=9 rusage=written  ru_maxrss=192
            control (arg5 NULL) rc=0 rusage=UNTOUCHED
    plexus: waitid rc=0 si_pid=3164893 si_status=9 rusage=written  ru_maxrss=256
            control (arg5 NULL) rc=0 rusage=UNTOUCHED

Both kernels honour arg5.

**And the target-side path is a pure pass-through, enumerated rather than
assumed** — `wait4()` (`lib/crtl/src/sys/wait.c:48`) -> `__pxx_wait4`
(`lib/rtl/pxxcio.pas:937`) -> `PalWait4` (`lib/rtl/platform.pas:931`) ->
`PalBackendWait4` (`lib/rtl/platform/posix/platform_backend.pas:1964`) ->
`__pxxrawsyscall(SYS_waitid, idtype, id, @si, wopts, Int64(rusage), 0)`. Four
hops, no NULL substitution (`waitpid` is the arm that passes 0, deliberately),
identical object bytes on both boxes. That riscv32 codegen really does place
arg5 in a5 is not reasoned — the same riscv32 binary writes rusage on plexus.

**This is an elimination, not a demonstration.** What remains standing is the
emulator, on a path enumerated above; nobody has shown the commit in qemu's
`linux-user/syscall.c` where `TARGET_NR_waitid`'s rusage copy-back landed. That
citation is the one open residual and would upgrade this from "only thing left"
to "mechanism". It is cheap for anyone with network access.

## What to do — three routes, and they are not exclusive

1. **Record the fingerprint.** `twatch` should capture the emulator, gcc and
   kernel versions beside `hw_fp` and print them in the report header. This is
   the ticket's own subject and it is what makes the class legible; without it
   the next instance costs another session the same afternoon.
2. **Upgrade seven's emulators.** Fixes this row and every future one in the
   class. Needs root on seven, so it is **the owner's call, not a lane's**.
3. **Treat it as a host capability, the way RDRAND already is.** `test-core#1058`
   is skipped on seven with *"host capability absent: rdrand — this CPU does
   not implement RDRAND/RDSEED, so the job cannot pass on this box and a red
   would be permanent"*, and is scored as a coverage hole rather than a red.
   An emulator too old to honour a syscall argument is the same shape. Note the
   grain differs: RDRAND skips a JOB, this is one ROW inside one.

Route 3 is the one that makes the tier honest without root and without giving
up the assertion, but it is testmgr surgery and it wants T's judgement on the
grain. **Do NOT weaken the row's riscv32 arm to accept either answer** — the
waitid rebuild is the most bespoke code on that path and this is the only row
that exercises its rusage argument; an assertion that cannot fail there is
worth less than a red that says why.

## Do not read this as "seven is wrong"

It is not. A verdict measured on an older emulator is a true statement about
that emulator, and seven is deliberately not plexus. The defect is that the
archive does not SAY which one it measured, so a true statement about a 2024
emulator is read as a statement about the compiler.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 17854b85b.

## Resolved 2026-09-05 by frankZ — route 1, landed before the upgrade lands

`twatch.py` now records what RAN a verdict, and every report carries it:

    toolchain: kernel=7.0.0-30-generic gcc=15.2.0 qemu=10.2.1(6 of 6) wasmtime=48.0.1
    toolchain_fp: 7ea30b40553c

**Ordering was the whole point.** seven is dist-upgrading to 26.04 today
(route 2, the owner's). Had the upgrade landed first, every archived verdict on
either side of it would have been indistinguishable from every other — the
divergence closed and the record of it never written, which is the same blind
instrument briefly agreeing with plexus. This lands first.

### What the guards are for, one per way the field could go quietly useless

- **The runner list is complete.** `RUNNER_BINARIES` is explicit rather than
  parsed out of `run_target.sh`, because a parse that stopped matching would
  shrink the fingerprint to nothing while still printing a line. The cost of
  being explicit is drift, so `twatch_toolchain_devtest.py` derives the set
  from `run_target.sh`'s own `exec` arms and fails when the two disagree —
  verified by dropping `qemu-xtensa` from the tuple, which reports
  `unfingerprinted: qemu-xtensa`. A new cross target whose emulator nothing
  fingerprints is the next instance of this bug.
- **Absence is PRINTED, not omitted.** A missing runner is the condition that
  produced six false regression tickets on 2026-09-04, all accusing the
  compiler, all caused by wasmtime not being installed. `wasmtime=ABSENT` is a
  measurement; a vanished entry is not. wasmtime is resolved the way
  `run_target.sh` resolves it — PATH then `~/.local/bin` — because reporting
  ABSENT for a box that runs it fine is the same defect pointing the other way.
- **A mixed toolchain cannot collapse.** The qemu entries collapse to one
  version only when they agree, and the collapsed form still says how many
  agreed (`qemu=8.2.2(6 of 6)`), so three-of-six cannot read as six.
- **The fingerprint moves on absence, not only on versions.** Installing
  wasmtime on seven changed what six jobs measured; a hash over only the
  versions found would have been identical before and after.
- **An older report is distinguishable from a toolchain that measured
  nothing.** Every report before today has no `toolchain:` line; the empty case
  renders `unrecorded (older harness)` and its fingerprint is `""` rather than
  a hash of `{}`, which would be a stable 12 hex that reads as a real
  toolchain a reader could then "match" against.

### The change announcement, which is the part that pays today

A toolchain change re-baselines every cross-target row at once and arrives
looking like ordinary noise — a batch of rows changing answer with no commit to
blame. So a report whose host's toolchain differs from its previous run now
opens with a callout naming both fingerprints, the way a hardware epoch does.
seven's upgrade is the first one it can see. Both directions controlled: a
differing stored fp emits it, an identical one does not.

### Scope, stated rather than implied

- **Verified by an end-to-end render, not by a live watcher run.** The archive
  has been quiet since `b668ba503` (2026-09-04T18:47:41Z, ~25h, planned — seven
  is upgrading), so no real report has exercised this yet. `write_report_md`
  was driven directly with a synthetic report and state, and the frontmatter
  and both callout directions were read off the file it wrote.
- **`TSTATE.md` does not render the toolchain yet.** Adding a column to the
  generated index is a separate small change and is NOT done here.
- The toolchain is latched top-level in each host's state (`st["toolchain"]`),
  deliberately not inside `st["last"]`, because `twatch_timeout_verdict_devtest`
  asserts that literal's shape by slicing a fixed window and a new key would
  push later fields out of it. Widening a guard's window to accommodate its own
  subject is not a fix.

## 2026-09-05 — the index half landed, and a correction to the commit that closed this

### CORRECTION: `17854b85b`'s ordering claim is FALSE against seven's clock

That commit message says the fingerprint landed before seven's dist-upgrade,
**on purpose**. Measured by the seven agent from `/var/log/dist-upgrade/main.log`:
the upgrade ran **15:20–17:30 UTC** and `17854b85b` is dated **17:45:34 UTC**.
It landed **fifteen minutes after the upgrade had already finished.**

The message is immutable, so the correction lives here, where anyone who reads
the field will arrive.

**What survives, and it is the part that matters:** the field landed after
seven's last *publish*, which is why `prev` is `None` on that host and why
`TOOLCHAIN FIRST RECORDED` had to be written. That is true and a reader can
check it. **"Beat the upgrade" is not.**

**How the error was made, because the mechanism is more useful than the fact.**
The ordering was reasoned from **repo time** — the commit landed today, the
upgrade was announced as happening today, therefore the commit beat it. The
refutation came from **the box's own log**. Two clocks, one question, and the
repo is the clock everybody has. Worse, the instruction in force was *do not ssh
to seven while it upgrades*, which is exactly why the claim went unmeasured:
**being told not to measure something is not a licence to assert it instead.**
The honest move under that constraint was to say "I do not know whether this
beat the upgrade", which costs one clause and is the whole of the difference.

The ticket was still the right thing to do first. The urgency was real. The
specific claim that the sequencing had been *achieved* is the one thing that
could not be checked and the one thing that got written down.

### The third cause: no baseline is not no change

`prev` is read from the host's own state, and on 2026-09-05 **neither host had
ever latched one** — `seven.json` and `plexus.json` both had no `toolchain` key,
and `grep -rl toolchain_fp devdocs/progress/tstate/reports/` returned **0 files**.
So `if prev and now_fp and prev != now_fp` was False by the first conjunct, and
seven's first post-upgrade report **could not fire the CHANGED callout at all**,
upgrade or no upgrade.

That is a **third cause for "no callout"**, and it is indistinguishable from the
two that were already named — the render is broken, or the watcher died. It was
the one that was true. A watch scoring the absence would have charged a correct
report to a defect.

Reached independently by two sessions from instruments that **fail
differently**: frankZ read the state files (a stale checkout would have fooled
it); the seven agent grepped the report archive (a bad pattern would have fooled
it). Neither failure mode is shared, so this is corroboration and not agreement.

**Fixed rather than documented.** A first-ever report now says so itself:

> **TOOLCHAIN FIRST RECORDED on this host** (`<fp>`). There is no previous
> fingerprint on this box to compare against, so the absence of a CHANGED
> callout above means *no baseline existed*, not *nothing changed*.

Four guards in `twatch_toolchain_devtest.py` hold the two silences apart, driven
through the real `write_report_md` rather than through a restatement of the `if`:
first-ever says FIRST RECORDED and does not claim a change; unchanged says
nothing; a real move says CHANGED and not FIRST RECORDED.

### DECIDED, not omitted: no reconstructed baseline is seeded into the archive

A pre-upgrade fingerprint is reconstructible from apt history and the
dist-upgrade logs, and seeding it into `st["toolchain"]["fp"]` would make the
next report fire the CHANGED callout with plausible values. **Two sessions
independently declined, for the same reason**, and the owner was asked rather
than either session acting.

The decisive argument is not "the reconstruction might be wrong". It is
frankuser's, and it is stronger: the reconstruction reads kernel **6.8.0-139**
while frankZ's direct measurement on seven on 2026-09-04 read **6.8.0-138**, and
a routine kernel update in that window makes **both true, of different moments**.
So **"the" pre-upgrade fingerprint is not well defined** — the box held more than
one toolchain state inside the window, and a seed must pick one and present it as
*the* baseline with nothing in the record saying which moment it describes.

`fp_of_toolchain` hashes the whole dict including **absence**, so a one-digit
difference, or a wrong guess about whether wasmtime was installed, yields a
completely different fingerprint. The instrument would then announce a
transition it never observed — the precise failure this ticket exists to
prevent, one layer up.

**A recovery that cannot terminate is not a recovery.** No further digging on
seven can settle which moment the baseline should describe.

And it is unnecessary: `toolchain:` is spelled out in full and unconditionally,
and seven's pre-upgrade versions are recorded in this ticket verbatim (qemu
8.2.2 uniformly, kernel 6.8.0-138, gcc 13.3.0, measured 2026-09-04). **Diff the
new report's `toolchain:` line against that table and the transition is
readable.** It is recoverable as a READING; it is not recoverable as a
FINGERPRINT, and the two must not be closed into each other.

If the owner overrides, the condition put to him is that the seeded entry carry
`reconstructed: true` **and the moment it claims to describe** — otherwise it
inherits the same defect one level down.

### `TSTATE.md` now renders it — the scope item this ticket left open

The previous section said *"`TSTATE.md` does not render the toolchain yet ... a
separate small change and is NOT done here"*. Done now, as `toolchain_block()`.

Deliberately a **separate function**, not extra rows inside
`cross_currency_block`: that block's devtest asserts its shape by counting the
`| ` rows it emits, and appending a table there took two rows to four. Widening
a guard's window to accommodate its own subject is not a fix — and applying that
rule to one's OWN guard is the direction where loosening is easiest to justify.

A host with no stored toolchain renders as `_not published since this field
existed_`, in words, never as a blank cell. **A blank in a comparison table reads
as agreement**, which is this ticket's own defect one layer up.

The heading is top-level rather than a `###` under cross-currency, because that
block returns `[]` when no host has a dated full tier and an orphaned subheading
reads as part of whatever section preceded it.

### The instrument lesson nobody had: LANDED is not LIVE

From frankuser, on seven, and it belongs with the rest of today's family. **The
clone contained `17854b85b` and the running daemon did not.** The process had
started before the fetch, so it executed `twatch.py` at `065bb7eaf0d5` while the
file on disk was `7327e547732c`. **`git merge-base --is-ancestor` answered
`true` the whole time, correctly** — about the clone, which was not the subject
of the question. Only `./trackt status`'s `code :` row showed it, as `STALE`.

"The clone has the commit" and "the running process is executing the commit" are
different claims, and the first is the one everybody checks. Same animal as
`tail`'s exit status and a neighbouring gate's `summary.log`: a correct answer
about a different subject. Written up in `devdocs/dev/debugging-playbook.md`.

The unit was also `active` but **`disabled`** — true right now, and silent about
the next boot. A fourth member of the same family.
