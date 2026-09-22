---
slug: task-t-run-c-crtl-wait-on-borg-under-qemu-10-2-1
track: T
prio: 40
type: task
status: new
owner: ""
created: 2026-09-22
found-by: frankz-e5
tags: [riscv32, qemu, tstate, borg, confound, wait4]
blocked-by: []
summary: "ONE COMMAND ON borg DECIDES A p55 TRACK-A TICKET, AND NO SEAT CAN REACH THE BOX. Run `test/c_crtl_wait.c` for riscv32 on borg under a **qemu-riscv32 10.2.1** invoked from a path (NOT installed system-wide, NOT a package change, NO sudo) and diff against borg's own gcc oracle, then report the verdict on `bug-a-wait4-does-not-write-rusage-on-riscv32`. WHY IT IS WORTH A TICKET RATHER THAN A MESSAGE: that row has only ever failed under qemu 8.2.2, which across the 1,082 of 2,971 tstate reports recording a toolchain is PERFECTLY COLLINEAR with both the host and gcc — every row is `gcc=13.3.0 qemu=8.2.2` (700, borg, RED) or `gcc=15.2.0 qemu=10.2.1` (382, seven, GREEN), no other pair exists. Three variables move together, so the archive has ZERO rows that could separate them and no amount of further sampling will make one. On borg, gcc and the host and the kernel hold still and **qemu moves alone**, which is why this single run breaks a three-way collinearity that 2,971 reports cannot. GREEN indicts the emulator and the A ticket is not a syscall bug; RED leaves gcc and an unnamed host difference standing together and the A ticket keeps its current shape. WHY NOBODY HAS DONE IT: all ten interactive sessions are tmux panes on plexus, which was retired 2026-09-11T20:19:53Z to borg, so there is NO interactive seat on borg — this is a borg-side operation by construction, which is what makes it T's and not A's. Do NOT satisfy this by installing or upgrading a package: that is sudo, therefore the owner's, and it is not what the question needs. frankb-8e already ran the plexus arm (GREEN, qemu 10.2.1, gcc 15.2.0) and it REPLICATES seven's cell rather than adding one, so it does not answer this."
---

# Run `c_crtl_wait.c` on borg under qemu-riscv32 10.2.1

**The whole task is one compile and one run, and its value is entirely in
*where* it runs.**

    ./compiler/pascal26 --target=riscv32 test/c_crtl_wait.c -o /tmp/<scratch>/out
    <path-to>/qemu-riscv32-10.2.1 /tmp/<scratch>/out

diffed against borg's own gcc oracle for the same source, looking at the
`wait4-rusage` line specifically (`rusage=written` versus `rusage=UNTOUCHED`).

## Why this is not "just re-run the failing row"

The row already fails on borg under its installed qemu 8.2.2, and has ~700 times.
Re-running it produces row 701 of a table that cannot answer the question, because
**host, gcc version and qemu version are perfectly collinear in every observation
this fleet has ever recorded.** The empty cells are the informative ones and no
amount of ordinary sampling fills them.

This task fills one: **same host, same kernel, same gcc, same pxx binary, emulator
moved by hand.**

## Constraints, and they are the reason this is specified rather than assumed

- **Invoke a 10.2.1 binary by path. Do not install, upgrade, or change a package.**
  A dist-upgrade is `sudo`, therefore the owner's, and it is also not what the
  question needs — the question needs one process run under one emulator.
- **Do not satisfy this on plexus or any other host.** `frankb-8e` already ran that
  arm: GREEN, `qemu=10.2.1`, `gcc=15.2.0`, tree `3e381e41d`. It lands in the cell
  seven already occupied, so it REPLICATES that cell on a second machine rather
  than adding one. It does eliminate *"something about seven the machine"*, which
  is worth having and is recorded in the A ticket; it does not touch gcc.
- **Report the emulator's identity, not the intent.** Read the version off the
  binary actually executed. `tools/run_target.sh riscv32` is a bare
  `exec qemu-riscv32`, i.e. a PATH lookup, so which binary runs is an environment
  fact and not a property of the command.

## What to do with the answer

Write the verdict into
`bug-a-wait4-does-not-write-rusage-on-riscv32` (backlog-core, p55) and say which
qemu binary produced it. That ticket already carries the full analysis and both
outcomes are written up there; this one exists only because the measurement is
unreachable from where every seat currently sits.

**Do not re-rank the A ticket on the strength of a green here** without reading its
last two sections — its prio is justified under both outcomes, for different
reasons, and that is stated there deliberately.

## Provenance

Collinearity counted by `frankz-e5` over `devdocs/progress/tstate/reports/*.md`;
plexus arm measured by `frankb-8e`; the emulator-split hypothesis and the
seven-retirement timing are `frankb-8e`'s. Neither of us has run this row on borg
and neither of us can.
