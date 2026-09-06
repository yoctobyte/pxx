---
slug: bug-n-pypal-arm32-getdents64-is-unfilled
title: "pypal's arm32 NR_GETDENTS64 is -1 — os.listdir fails loudly there, pending a number from an arm32 header"
track: N
type: bug
prio: 30
status: done
found: 2026-08-29
found-by: claude-N
---

# arm32 has no getdents64 number, on purpose

`os.listdir` landed 2026-08-29 with `NR_GETDENTS64 = -1` in pypal's arm32
block, so it raises there:

> os.listdir: this build has no getdents64 number for this target

Every other target has a header-verified number (x86-64 217, i386 220,
aarch64 61, riscv32 61).

## Why it was left rather than filled

The machine the work was done on carries **no arm32 syscall table**:
`arch/arm/tools/syscall.tbl` is absent from the installed kernel headers, and
`arch/arm64/include/asm/unistd32.h` does not list it by name.

It cannot be derived from a sibling, and that is not caution — it is
arithmetic. i386 and arm32 sit **+27 apart** for `openat` (295/322),
`unlinkat` (301/328), `renameat` (302/329), `ppoll` (309/336) and
`readlinkat` (305/332), so an offset looks like a rule. It is not one:
`getdents64` is **220 on i386 and 217 on arm32**. Applying the offset yields
247, which on arm32 is a different syscall entirely.

A wrong number here does not fail — it issues an unrelated syscall, on the one
target of six least likely to be executed. `-1` is the table's own "no such
call" sentinel and turns that into a loud refusal.

## The fix

One line, from an authoritative arm32 source:

```pascal
{$ifdef CPU_ARM32}
  NR_GETDENTS64 = <from arch/arm/tools/syscall.tbl>;
```

Take it from an arm32 kernel header or `arch/arm/tools/syscall.tbl` in a
kernel tree — **not from memory and not from another architecture.** The
widely-cited value is 217; this ticket exists precisely because "widely cited"
is not the standard the rest of that table is held to.

## Gate

A `.npy` calling `os.listdir` cross-compiled for arm32 and run (qemu-arm or
hardware). Native x86-64 green says nothing about this ticket — that is the
whole point of it.

## See also

`NR_CLOCK_GETTIME` for arm32 IS filled (403) and did not need this treatment:
the time64 block was deliberately assigned identical numbers on every 32-bit
ABI, which is checkable from two independent sources on any machine (i386's
header and the kernel's generic `syscall.tbl`). Different kind of number,
different amount of evidence available.

## RESOLVED 2026-09-06 (frank-subcoord, Track N)

`NR_GETDENTS64 = 217` for arm32 in `compiler/builtin/pypal.pas`.

**The original refusal to derive it was right, and the number was already in the
ticket.** This ticket argued that the i386/arm32 +27 offset (openat, unlinkat,
renameat, ppoll, readlinkat) does NOT extend to getdents64 — and cited i386 220,
arm32 217 while making that argument. What was missing was not the value but a
source the author trusted: that machine had no `arch/arm/tools/syscall.tbl`.

**Three instruments now, and they fail differently.**
1. `devdocs/dev/syscall-maps/arm32.txt` — a qemu `-strace` SWEEP, not a header
   read — has `217 getdents64`. This is the instrument the original author did
   not have; it is an oracle about qemu, which is the whole population that
   runs cross-target tests here.
2. This ticket's own text, which cites 217 while arguing the offset fails.
3. **`os.listdir` run end to end under qemu-arm**, which is the one that counts,
   because a wrong number here does not fail — it issues an unrelated syscall.

```
arm32, built by the PIN (NR_GETDENTS64 = -1):  Unhandled exception
arm32, built by this fix:  ['alpha.txt', 'beta.txt', 'gamma.txt', 'ls.py', ...]
```

x86-64, i386 and aarch64 unchanged and still correct; riscv32 cannot reach
`import os` at all yet (`bug-a-nilpy-on-cross-targets-four-remaining-walls`).

Note 217 is also x86-64's getdents64. Same number, unrelated tables — that
coincidence is exactly the kind of thing that makes a derived number look
plausible, so it is written down rather than left to be rediscovered.

**Gate:** `make compiler/pascal26` — `converged after 1 round(s)`.
`tools/gate.sh quick` green.

**Inert until pinned: YES** — compiler builtin.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
