---
slug: bug-a-loadfile-runtime-wrappers-have-no-riscv32-or-xtensa-arm
track: A
prio: 45
type: bug
found: 2026-08-30
owner: unassigned
---

# LoadFile's runtime syscall wrappers have no riscv32 or xtensa arm

`PXXStrLoadFile` in `compiler/builtin/builtinheap.pas` calls four per-target
syscall wrappers. Three of them cover four architectures and not the two 32-bit
generic ones:

| wrapper | has arms for | missing |
| --- | --- | --- |
| `PXXSysOpenRO` | x86-64, i386, arm32, aarch64 | **riscv32, xtensa** |
| `PXXSysLseek` | x86-64, i386, arm32, aarch64 | **riscv32, xtensa** |
| `PXXSysClose` | x86-64, i386, arm32, aarch64 | **riscv32, xtensa** |
| `PXXSysRead` | x86-64, i386, arm32, aarch64, riscv32, xtensa | — |

`PXXSysRead` already having both arms is the tell that this is drift, not a
decision: one of the four was extended and its three siblings were not.

The `{$else}` returns `-1`, and its comment says exactly why that is right:
*"Returning the POSIX failure value is the whole point"* — an armless target
that left `Result` unassigned made `if fd < 0 then Exit` read the return slot's
leftover bytes. So the failure here is honest, but it is **silent**:
`PXXStrLoadFile` returns nil and `LoadFile` publishes an EMPTY string.

## Why this is filed and not fixed, and why the codegen was HELD

Found while adding the `SysOpen` family and `LoadFile` to `ir_codegen_xtensa.inc`
and `ir_codegen_riscv32.inc` (a bounded grant covering those two files). The
`SysOpen` family landed and is green on both backends against the x86-64 oracle.

The `LoadFile` codegen arm was **written, measured, and deliberately not
landed.** It is correct — the refcount dance is all a backend owns there, the
file I/O is entirely in the helper — but with the wrappers missing it turns

    error: this builtin has no arm in the xtensa backend (builtin -100)

into a program that compiles and prints nothing. **The compile error is the
safety property here**, and trading a diagnostic for a silent empty string is a
regression even though it closes a feature gap. The arm is banked at
`scratchpad/rw/loadfile-xtensa.arm` and should land in the SAME change as the
wrappers, never before them.

## The numbers, already measured

Both tables were probed for the `SysOpen` family that landed alongside this, so
whoever picks this up does not need to re-derive them:

| | riscv32 (asm-generic) | xtensa (its own table) |
| --- | --- | --- |
| `openat` | 56 | 288 |
| `read` | 63 | 12 |
| `write` | 64 | 13 |
| `close` | 57 | 9 |
| `lseek` | 62 — but see below | 15 |
| `fchmod` | 52 | 52 |

**riscv32 has NO plain `open`**, so `PXXSysOpenRO` must use
`openat(AT_FDCWD = -100, path, 0, 0)` there; xtensa still carries a legacy
`open` (8) but should use `openat` too, so the two read the same. `lseek` on
rv32 is the `_llseek` split-offset question the existing riscv32 block in
`lib/rtl/platform/posix/platform_backend.pas` already documents — for source
loads the plain form is what qemu-user tolerates, which is the same call
i386/arm32 already make.

## Gate

`make compiler/pascal26` to fixedpoint, then `test_cross_loadfile` against the
x86-64 oracle on riscv32 and on xtensa in BOTH ABIs, plus the cross differential
for regressions. Un-SKIP the `test_cross_loadfile` rows in `test-riscv32` and add
the xtensa one — the riscv32 SKIP comment in the Makefile points here by slug.

Same family as `bug-a-xtensa-cannot-read-a-managed-string-out-of-a-record-field-
or-array-element`: a rule most targets carry and the two without a working
oracle were skipped for.
