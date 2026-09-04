---
track: T
prio: 70
type: bug
status: backlog
found: 2026-09-04
found-by: frankZ
owner: ""
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
