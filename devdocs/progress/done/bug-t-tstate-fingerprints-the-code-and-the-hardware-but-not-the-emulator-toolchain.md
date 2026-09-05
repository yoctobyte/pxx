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
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

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
