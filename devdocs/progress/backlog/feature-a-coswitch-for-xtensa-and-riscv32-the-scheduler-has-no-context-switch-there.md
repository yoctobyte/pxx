---
slug: feature-a-coswitch-for-xtensa-and-riscv32-the-scheduler-has-no-context-switch-there
track: A
prio: 30
type: feature
blocked-by: []
status: backlog
summary: "EmitCoroutineRuntime covers x86-64/i386/aarch64/arm32 and refuses wasm32; xtensa and riscv32 fall through SILENTLY by design, so CoSwitchAddr is never set. Today that is harmless because the scheduler cannot compile for either target anyway — it has no syscall block for them. The moment either gets one, six programs stop erroring and start jumping into code that was never emitted, onto a stack primed with the x86-64 frame layout. Found while filling xtensa's syscall table; the numbers were deliberately NOT added for this reason."
owner: unassigned
---

# CoSwitch for xtensa and riscv32

## What is missing

`compiler/coroutine_emit.inc`'s `EmitCoroutineRuntime` has arms for
`TARGET_X86_64`, `TARGET_I386`, `TARGET_AARCH64`, `TARGET_ARM32`, and an
explicit `Error` for `TARGET_WASM32`. Its closing comment:

> *Other targets land in later phases (riscv32/xtensa) — they fall through
> silently ON PURPOSE and are left alone here; making THEM loud belongs to
> refactor-a-target-dispatch-chains-fail-open, not to a registration ticket
> that must leave every existing target byte-identical.*

That was a correct call at the time. This ticket is the "later phase".

## Why it is not currently visible, and what makes it visible

`lib/rtl/scheduler.pas` carries its own per-arch syscall block — `SYS_gettid`,
`SYS_epoll_create1`, `SYS_epoll_ctl`, `SYS_epoll_wait`/`_pwait`, `SYS_fcntl`,
`SYS_timerfd_*` — for x86-64, i386, aarch64, arm32 and **nobody else**. So on
xtensa and riscv32 every scheduler program dies at compile time with
`undefined variable (SYS_gettid)`, long before anything could call `CoSwitch`.

**The compile error is the only guard.** Filling in the numbers is a two-line
change that anyone would read as obviously safe, and on its own it would
convert six honest compile failures into six programs that build and jump to an
address that was never emitted, having primed the coroutine stack with the
`{$else}` fallback — the **x86-64** pop order (8 qwords: exc, r15, r14, r13,
r12, rbx, rbp, ret) — on a 32-bit target with different callee-saved registers.

This is the inverse of the usual reading of "a missing op hides every bug in
the programs it stops from compiling". Normally the block is concealing a
defect and removing it is pure gain. Here the block *is* the safety property,
and removing it alone is a regression that looks like six more green rows.

The numbers are already measured and are recorded here so that whoever does the
A work does not have to re-derive them, and so that nobody fills them in
*without* doing the A work:

| | xtensa | riscv32 (asm-generic) |
| --- | --- | --- |
| `gettid` | 127 | 178 |
| `epoll_create1` | 275 | 20 |
| `epoll_ctl` | 19 | 21 |
| `epoll_wait` / `_pwait` | `epoll_wait` 18, `epoll_pwait` 274 | `epoll_pwait` 22 |
| `fcntl` | 67 | 25 |
| `read` / `close` | 12 / 9 | 63 / 57 |
| `timerfd_create` / `_settime` | 312 / 313 | 85 / 86 |

(The xtensa column is measured — one syscall per process under
`qemu-xtensa -strace`, with all five of the repo's established anchors
reproduced exactly. The riscv32 column is asm-generic, i.e. aarch64's, and is
recall, not measurement; verify it before use.)

## The three parts, all of which must land together

1. **`compiler/coroutine_emit.inc`** — a `CoSwitch` for each target: push the
   callee-saved set plus `BSS_EXC_TOP`, store sp into `[a0]`, load sp from
   `[a1]`, restore, return. Must be reached by `call`, never inlined. **Track A.**
   xtensa has the extra wrinkle that the two ABIs differ: Call0 has an ordinary
   moving sp and a normal callee-saved set, while windowed rotates the register
   file on `call8` and needs the window spilled before the stack can be handed
   to another context — a windowed `CoSwitch` is a materially harder problem
   than a Call0 one, and the two should be sequenced, not bundled.
2. **`lib/rtl/scheduler.pas`** — the syscall block above, an `epoll_event`
   layout (both targets are 32-bit and need the explicit pad word that
   aarch64/arm32 use, not x86's packed record), and a `SpawnSized` priming block
   whose slot count and return-address offset match part 1's pop order exactly.
   **Track B.**
3. The six rows wired into `test-xtensa` / `test-riscv32`: `test_asyncecho`,
   `test_channel`, `test_reactor`, `test_scheduler`, `test_scheduler_exc`,
   `test_timer`.

Part 2 is worthless without part 1 and dangerous alone, which is the whole
reason this is one ticket and not two.

## Provenance

Found while adding xtensa's row to `lib/rtl/platform/posix/platform_backend.pas`
([[feature-s-the-xtensa-row-of-the-posix-syscall-table]]). That ticket unblocks
8 of the 14 compile failures and leaves these 6 deliberately red.
