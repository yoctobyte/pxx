---
track: A
prio: 55
type: bug
blocked-by: []
summary: "`wait4()` does not write its `rusage` out-parameter on riscv32, and does on every other cross target. MEASURED 2026-09-12 on borg, full native tier, job `test-core#2020` (`test/c_crtl_wait.c`): `expect_same MISMATCH [riscv32/c_wait26]`, `- wait4-rusage rusage=written` / `+ wait4-rusage rusage=UNTOUCHED`. i386, arm32 and aarch64 all OK on the same row, so it is the riscv32 syscall path and not the C test or the crtl shim. NOT environmental — found alongside a multilib fix on that box and explicitly separated from it: the other two rows in that tier went green when multilib landed, this one did not move. One-target width/ABI shape, which is the class x86-64-only development is structurally blind to. No skip was added and nothing was deleted."
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
