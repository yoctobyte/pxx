---
track: A
prio: 55
type: bug
blocked-by: []
summary: "`wait4()` does not write its `rusage` out-parameter on riscv32, and does on every other cross target. MEASURED 2026-09-12 on borg, full native tier, job `test-core#2020` (`test/c_crtl_wait.c`): `expect_same MISMATCH [riscv32/c_wait26]`, `- wait4-rusage rusage=written` / `+ wait4-rusage rusage=UNTOUCHED`. i386, arm32 and aarch64 all OK on the same row, so it is the riscv32 syscall path and not the C test or the crtl shim. NOT environmental — found alongside a multilib fix on that box and explicitly separated from it: the other two rows in that tier went green when multilib landed, this one did not move. One-target width/ABI shape, which is the class x86-64-only development is structurally blind to. No skip was added and nothing was deleted. UPDATED 2026-09-22 -- THE HOST/VERSION HALF IS SETTLED AND THE CAUSAL HALF IS NOT, SO DO NOT PICK THIS UP AS A SYSCALL FIX WITHOUT READING THE LAST SECTION. Across the tstate reports that record a toolchain (1,082 of 2,971), qemu version partitions PERFECTLY by host: 700 borg all qemu=8.2.2, 382 seven all qemu=10.2.1, no crossover either way. The sibling done/regression-test-core-c-crtl-wait.md resolved this exact row on 2026-09-06 by the owner's dist-upgrade of SEVEN to 10.2.1 -- and seven was RETIRED 2026-09-11T16:29:49Z (plexus 20:19:53Z, both to borg), so this ticket's 09-12 borg measurement is the day after the last host carrying the remedy left the fleet. A done/ whose remedy was an ENVIRONMENT CHANGE is in force only while that environment exists, and nothing re-reads a closed ticket when a host retires. BUT THE PERFECT SPLIT IS PRECISELY WHY THE ARCHIVE CANNOT NAME THE CAUSE: host and qemu version are the SAME VARIABLE in this data, so zero rows separate 'borg's qemu is old' from 'borg differs from seven some other way', and the table would look identical if qemu were irrelevant. NOBODY HAS VERIFIED THAT 10.2.1-vs-8.2.2 MOVES THIS ROW -- frankb-8e verified only which host ran which version and says so. THE WHOLE QUESTION IS ONE RUN: c_crtl_wait.c on borg under a 10.2.1 qemu-riscv32, invoked not installed, which breaks the confound by moving one variable. If that is the remedy it is sudo and therefore the OWNER'S, not a seat's -- deliberately NOT escalated yet, because asking him for sudo on an unverified premise spends the one resource that cannot be parallelised on a question a single run answers. Not re-ranked: the previous author's prio-55 reasoning is untouched. Host pairing and retirement dates measured by frankb-8e, re-counted by frankz-e5; neither has run the row. REFINED LATER THE SAME DAY: gcc IS A THIRD PERFECTLY COLLINEAR VARIABLE, so the confound is THREE-WAY, not two. Every report recording a toolchain pairs gcc=13.3.0 with qemu=8.2.2 (700, borg, RED) or gcc=15.2.0 with qemu=10.2.1 (382, seven, GREEN); no other pairing exists. frankb-8e ran the row on PLEXUS and it is GREEN (qemu 10.2.1, gcc 15.2.0, tree 3e381e41d) and labelled it NOT decisive, which is right -- it lands in the cell seven already occupied, so it REPLICATES that cell on a second machine rather than adding one. It does eliminate 'something about seven the machine'; it does NOT touch gcc, contra 8e's own stated reason, since seven was also 15.2.0. Mechanistic plausibility favours qemu (rusage is syscall emulation) but that is REASONING, not measurement, and the data cannot separate them. THE DECISIVE ROW IS UNCHANGED AND NOW BREAKS A THREE-WAY COLLINEARITY: c_crtl_wait.c on BORG under a 10.2.1 qemu-riscv32, invoked not installed, moves qemu alone because borg keeps gcc 13.3.0. AND NOBODY REACHABLE CAN RUN IT -- all ten peer sessions are tmux panes on plexus, which retired 2026-09-11 to borg, so there is no interactive seat on borg. It is a borg-side operation, i.e. Track T's box or the owner's, which is a different KIND of item from what this prio implies. Still not escalated and still not re-ranked. Archive gap closed: plexus's qemu is 10.2.1 as of today (measured; its 613 reports record none), which also means 8e's green is from a host the fleet no longer runs."
---

# wait4 leaves rusage untouched on riscv32

Reported by the Track T seat on borg, 2026-09-12, from a full native tier at
`051b229aa`. Flagged rather than chased, because it was not what that seat was
sent after.

## The measurement

```
test-core#2020  test/c_crtl_wait.c
  expect_same MISMATCH [riscv32/c_wait26]
  -  wait4-rusage     rusage=written
  +  wait4-rusage     rusage=UNTOUCHED
```

i386, arm32 and aarch64 pass the same row. **One target, same source, same
harness** — so the discriminator is the riscv32 syscall path.

## Why it is worth more than its prio suggests

This is the shape CLAUDE.md names as structurally invisible: the dev loop,
`gate.sh quick` and the pin all run on x86-64, so a defect that only appears on
one 32-bit cross target has no instrument pointed at it except the native tier
that found this. It was caught by breadth, which is what breadth is for.

`rusage=UNTOUCHED` is also the **default-collision** shape: an out-parameter that
was never written reads as a zeroed struct, which for most fields is a plausible
value. The test is right to assert *written* rather than a field's contents —
anything asserting the numbers would have to pick values, and a zero would pass.

## Where to start

`wait4` on riscv32: whether the syscall is issued with the rusage pointer at all,
and whether the argument register for the 4th parameter matches the kernel's
expectation on that ABI. Check the sibling `wait3`/`getrusage` paths in the same
file — **if one arm of a double case is fixed, grep for the sibling before
closing.** Compare against the arm32 path, which is the nearest working 32-bit
one.

---

## 2026-09-17 — THE ROW ANSWERS `written` ON RISCV32 HERE, AND THE ONE RECORDED DIFFERENCE IS THE EMULATOR

Re-measured on plexus at HEAD, on the arm this ticket names rather than on the
host's native one:

```
compiler/pascal26 --target=riscv32 test/c_crtl_wait.c  ->  qemu-riscv32  ->  wait4-rusage  rusage=written
compiler/pascal26              test/c_crtl_wait.c      ->  native x86-64 ->  wait4-rusage  rusage=written
stable_linux_amd64/default/pinned  same, native        ->                    wait4-rusage  rusage=written
```

**The pxx source is provably identical to what borg is testing.**
`lib/rtl/platform/posix/platform_backend.pas` — which holds the whole rv32
`SYS_waitid` path this row exercises — was last touched **2026-09-06**,
`677e75495`, **six days before this ticket's measurement**, and is an ancestor of
`ba8cf629926a`, the tree of the run that still reports the failure. Nothing in
the tree separates the two results.

**What does differ is recorded in the tier's own header:**

| | borg | plexus |
| --- | --- | --- |
| qemu | **8.2.2** | **10.2.1** |
| kernel | 7.0.0-29-generic | 7.0.0-31-generic |

**THIS DOES NOT SAY THE BUG IS NOT REAL — AND THE ORACLE IS THE REASON.**
`expect_same` compares pxx's output against a gcc-built oracle **run under the
same emulator**, and on borg the oracle prints `written` while pxx prints
`UNTOUCHED`. So qemu 8.2.2 *can* deliver rusage; something about the route pxx
takes does not get it. rv32 is the one target with no `wait4` syscall, so
`PalBackendWait4` reaches `SYS_waitid` with rusage in argument five while glibc's
`wait4` may reach it another way — and an emulator implementing the out-parameter
on one route and not the other would produce exactly this row, on exactly one
target, with the oracle passing.

**So the sharpened claim is narrower than either "pxx is wrong" or
"environmental":** the divergence is between pxx's rv32 route and the oracle's,
**under qemu 8.2.2 specifically**, and it disappears under qemu 10.2.1.

**WHAT THE TICKET'S OWN CONTROL DOES AND DOES NOT SEPARATE.** The summary says
*"NOT environmental — found alongside a multilib fix on that box and explicitly
separated from it: the other two rows in that tier went green when multilib
landed, this one did not move."* That control is sound and it rules out the
multilib change. **It does not vary the emulator**, because nobody had reason to
— and the emulator is the thing that actually differs between the two boxes.
A control separates you from the variable it moved, and from no other.

**What would settle it, and I can run none of it from here:** the same row under
qemu 8.2.2 on this box, or under qemu 10.2.1 on borg, or on real riscv32
hardware. Two of the three are a Track T operation on borg; the third is
hardware. **Until one of them runs, the prio-55 ranking should stay** — if it is
an emulator gap then the one-target-invisible-to-x86-64 argument in the body
still holds for a different reason, and if it is not, nothing here weakened it.

*Measured by the toko-watch seat, check-in 2i. Not re-laning, not re-ranking,
not claiming. Correcting my own check-in 2h in the same breath: I first "failed
to reproduce" this on x86-64 — a target this row does not even compare — and the
answer agreed with what I expected, which is why I stopped.*

## 2026-09-22 — THE HOST/VERSION HALF IS SETTLED, THE CAUSAL HALF IS NOT, AND THE ARCHIVE CANNOT SETTLE IT

Measured by `frankb-8e` off the tstate archive, independently re-counted by
`frankz-e5`; neither of us ran the row. This answers the *"what would settle it"*
question above in one direction only, and the direction it does NOT answer is the
one that decides what anybody does next.

### What is established

Pairing `^host:` against `qemu=` across `devdocs/progress/tstate/reports/*.md`:

```
700  borg    qemu=8.2.2
382  seven   qemu=10.2.1
```

Two qemu versions have ever been recorded and they partition **perfectly** by
host: no recorded borg run has seen 10.2.1, no recorded seven run saw 8.2.2.

**POPULATION, because a bare count is not re-derivable:** those 1,082 rows are the
reports that RECORD the field. A further **1,889 record no `qemu=` at all** (803
seven, 613 plexus, 359 borg, 114 xeon) — older reports predating the toolchain
fingerprint, which is `bug-t-tstate-fingerprints-the-code-and-the-hardware-but-not-
the-emulator-toolchain` (done/) being visible in its own archive. So "never" above
means *never in a report that says*, and `plexus` — which ran between the two —
records no version in any of its 613.

### The part that changes this ticket's standing

`seven` is the host the sibling ticket's remedy was applied to, and **`seven` was
retired 2026-09-11T16:29:49Z** (to plexus, itself retired 20:19:53Z the same day,
to borg) — `TSTATE.md` rows 6–7. This ticket's measurement is dated **09-12, the
day after the last host carrying the remedy left the fleet.**

So `done/regression-test-core-c-crtl-wait.md` is not wrong about what it did. It
resolved this row on 2026-09-06 by the owner's dist-upgrade of seven to qemu
10.2.1, and **its remedy did not travel**: the row is green on a machine that no
longer runs and red on the only machine that does. A `done/` whose remedy was an
environment change is in force only while that environment exists, and nothing
re-reads a closed ticket when a host retires.

This also disposes of *"it has survived at least four sampled shas today"* as
evidence of a persistent code defect (8e's own phrase, withdrawn by 8e). One box
answering the same way four times is what a toolchain delta looks like through a
code-shaped instrument.

### AND THE PERFECT SPLIT IS WHY THE CAUSAL HALF CANNOT BE READ OFF THE ARCHIVE

**Host and qemu version are the same variable in this data.** Every borg report is
an 8.2.2 report; every seven report is a 10.2.1 report. The partition is not
merely correlated, it is total — so the archive has **zero** rows that could
separate *"borg's qemu is old"* from *"borg differs from seven in some other way"*
(kernel, gcc 13.3.0, CPU, filesystem, load). The tidiness that makes the table look
conclusive is exactly what makes it uninformative about cause, and it would look
identical if qemu were irrelevant.

**NOBODY HAS VERIFIED THAT 10.2.1-VS-8.2.2 IS WHAT MOVES THIS ROW.** 8e states this
explicitly about its own measurement: it verified which host ran which version, and
the causal claim is still only the closed ticket's word. Stated here because the
two halves will otherwise travel together, and the second one is load-bearing for
the remedy.

### What would settle it now — and it is smaller than before

The original three options stand, but the archive has removed the need for two of
them. **One run of `test-core#src:test/c_crtl_wait.c` on borg under a 10.2.1
qemu-riscv32 — not installed system-wide, just invoked — decides it**, because it
breaks the confound: same host, same kernel, same gcc, same binary, one variable
moved. Green means the remedy is a qemu upgrade; red means seven differed from borg
in something nobody has named and this ticket is still about the riscv32 syscall
path.

**IF it turns out to be the upgrade, the remedy is `sudo` and therefore the
owner's, not a seat's** — 8e's point, and it is the difference between a ticket
someone can pick up and one that needs escalating. **NOT ESCALATED AND NOT
RE-RANKED, deliberately:** we do not yet know that the remedy is the upgrade, and
asking the owner for a sudo action on an unverified premise spends the one resource
that cannot be parallelised on a question a single run answers. The prio-55 reason
the previous author gave is untouched by everything above.

*`frankz-e5`, coordinator. I measured the host/version pairing and the retirement
dates and nothing else; the row itself I have never run. Lane note for the record:
8e read this as Track C off the failing step — a `.c` file under crtl — and the
fleet laned it A. It is A because the discriminator is the riscv32 syscall path,
which is CLAUDE.md's "do not guess the lane from the failing step".*

## 2026-09-22, LATER — gcc IS A THIRD COLLINEAR VARIABLE, THE PLEXUS ROW IS A REPLICATION NOT A NARROWING, AND NO REACHABLE SEAT IS ON borg

`frankb-8e` ran the row on **plexus** and labelled it, correctly and unprompted, as
NOT the decisive row:

```
host=plexus  qemu-riscv32=10.2.1  gcc=15.2.0  tree=3e381e41d  compiler=59b5bf39acd1
pascal26 --target=riscv32 test/c_crtl_wait.c + tools/run_target.sh riscv32
diffed against this box's own gcc oracle: IDENTICAL, rc=0
```

It could not meet the same-host condition because **this seat and 8e are both on
plexus**, not borg. Its self-assessment was right and its stated REASON was wrong,
in the direction that matters.

### The correction: gcc is not eliminated, it is confounded

8e wrote that the row raises the price of the rival hypothesis *"because plexus is
gcc 15.2.0 and seven is not"*. Seven **is** 15.2.0. Counted over every report that
records a toolchain (`frankz-e5`, `devdocs/progress/tstate/reports/*.md`):

```
700  gcc=13.3.0  qemu=8.2.2     (borg,  this row RED)
382  gcc=15.2.0  qemu=10.2.1    (seven, this row GREEN)
```

**No other pairing exists.** So host, gcc and qemu version are not merely
confounded pairwise — all three are **perfectly collinear**, and the plexus row
lands in the cell seven already occupied (`gcc=15.2.0`, `qemu=10.2.1`, green). It
is a REPLICATION of that cell on a second physical machine, not a new cell.

**What it therefore does and does not buy.** It does eliminate *"something about
seven the machine"* — a different box with the same toolchain gives the same
verdict, which is worth having and was not knowable before. It does **not** touch
gcc, which stands as an equal-standing rival to the qemu explanation on exactly the
same evidence.

**Mechanistic plausibility favours qemu** — whether `wait4` writes its `rusage`
out-parameter is syscall emulation, and the compiler that built the oracle has no
obvious route to it. **That is reasoning, not measurement, and it is recorded here
as the weaker thing it is.** The whole point of this section is that the data
cannot distinguish them.

### The decisive row is now MORE decisive, for a new reason

One run of `c_crtl_wait.c` on **borg** under a 10.2.1 `qemu-riscv32`, invoked and
not installed, breaks a **three-way** collinearity rather than a two-way: borg
stays at `gcc=13.3.0` and at its own kernel and hardware, so qemu moves alone.
Green indicts qemu; red leaves gcc and the unnamed-host-difference hypotheses
standing together.

### AND NOBODY REACHABLE CAN RUN IT

`frankz-e5`, 2026-09-22: **all ten peer sessions are local tmux panes on plexus**,
and plexus was retired 2026-09-11T20:19:53Z to borg. There is no interactive seat
on borg to ask. So the decisive row is not "a two-minute ask" of anyone in this
fleet — it is a **borg-side operation**, which makes it Track T's box or the
owner's, and that is a different kind of item from what this ticket's prio implies.
Recorded rather than escalated, per the reasoning in the section above: the run is
free for whoever is on borg and the premise is still unverified.

### Archive gap closed, with its own expiry noted

This ticket previously recorded that **613 plexus reports carry no `qemu=` field**.
8e measured plexus's value today: `/usr/bin/qemu-riscv32` `10.2.1 Debian
1:10.2.1+ds-1ubuntu3.2`, the only one on PATH (`tools/run_target.sh riscv32` is a
bare `exec qemu-riscv32`); the espressif fork at 9.2.2 is a different fork and off
PATH. Worth banking because plexus is retired and nobody was going to measure it
later — **and for the same reason 8e's green is not "the fleet is green here"**, it
is a green on a host the fleet no longer runs.

*8e declined to install qemu 8.2.2 on plexus to do the same-host flip: it leaves
the machine and is not a seat's call. Recorded because declining was correct and
the alternative would have produced a same-host crossover row obtained by an act
nobody authorised.*

