---
slug: feature-a-coswitch-for-xtensa-and-riscv32-the-scheduler-has-no-context-switch-there
track: A
prio: 30
type: feature
blocked-by: []
status: done
summary: "LANDED 2026-09-24 FOR THE CALL0 ABI, WHICH IS THE DEFAULT AND THEREFORE THE WHOLE PRACTICAL HOLE. All three parts the body says must ship together did: (1) an xtensa Call0 CoSwitch in coroutine_emit.inc plus the IR_COSWITCH lowering in ir_codegen_xtensa.inc -- the stub arm and the IR arm in ONE commit, because a lowering without a stub calls address 0; (2) scheduler.pas's xtensa arms -- syscall block, epoll_event layout, and the SpawnSized priming; (3) six rows in test-xtensa (scheduler, scheduler_exc, channel, timer, reactor, asyncecho) asserted against the x86-64 build of the same source, plus an esp32s3-vs-esp32c3 lib_asyncnet6 --emit-obj parity row. All six MATCH the x86-64 oracle under qemu-xtensa, and esp32s3 now builds lib_asyncnet6 where only esp32c3 could. THREE SLOTS, NOT THIRTEEN, AND THE AUTHORITY IS THE JMPBUF: exception_emit.inc's xtensa Call0 jmpbuf saves exactly (a15, sp, a0), so the switch matches it rather than the ABI's nominal a12-a15 -- if that stops being true the exception stub is wrong the same way and both move together. EVERY SYSCALL NUMBER WAS MEASURED BY NAME under qemu-xtensa -strace rather than copied: two would have been wrong from any plausible guess (asm-generic 222 is `Unknown syscall` here, and 64 is `utime`, not mmap2), and xtensa is NOT time64 unlike riscv32 -- timerfd_settime(313) is live and 410 is absent, so it must NOT get SCHED_TIME64. THE palthread LANDMINE HAS A SIBLING, now fixed: scheduler.pas had MAP_ANON_PRIV = $22 outside the arch split, and on xtensa MAP_ANONYMOUS is $800 -- the wrong value does not fail loudly, it returns EBADF and falls back to GetMem, silently losing the guard page. WHAT REMAINS IS THE WINDOWED ABI ONLY, sequenced not bundled as this body asks, refused BY NAME with a negative-control row asserting the refusal: feature-a-a-windowed-abi-coswitch-for-xtensa. THE CONDITION THAT WOULD MAKE THIS A TRAP AGAIN is unchanged in mechanism and now has a guard: the refusal at coroutine_emit.inc's tail being removed or routed around without a windowed stub landing in the same commit."
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

---

## `palthread.pas` landmine — read this before you lift the `__pxxclone` guard

Found by frank-coordinator grepping for the sibling of the `PalBackendMmapAnon`
`MAP_ANONYMOUS` fix (`97e96fc1b`); scope corrected by frankS; the flag value
below is measured by frankA rather than cited.

**Not a bug today.** `lib/rtl/palthread.pas` defines `MAP_ANON_PRIV = $22` at
`:84`, used at `:161` to mmap every thread stack. That constant sits **outside**
the arch split, which starts at `:87`, while the syscall numbers sit **inside**
it — and both xtensa and riscv32 fall to the `{$else}` at `:120`, where
`SYS_mmap = -1` and the `__pxxclone` compile-error fires first. So nothing is
silently wrong right now.

**It becomes wrong the moment this ticket lands**, because lifting the guard
removes the thing that is currently saving it.

**The two targets are NOT symmetric — this is the part to get right:**

| | `SYS_mmap` | `MAP_PRIVATE\|MAP_ANONYMOUS` |
| --- | --- | --- |
| riscv32 | **222** (generic ABI), placeholder is `-1` | **`$22` = 34 — already correct**, same as x86-64/i386/aarch64/arm |
| xtensa | **80** (its own numbering; generic 222 is `Unknown syscall 222`) | **`$802` = 2050** — the sole outlier |

So: **when moving `MAP_ANON_PRIV` inside the arch split, xtensa takes `$802` and
every other arch takes `$22`** (frankS's wording, and the reason for it is that
a note grouping the two targets invites someone to "fix" riscv32's already-correct
`$22` to `$802` and reproduce the EBADF that `97e96fc1b` just removed).
riscv32 needs the syscall block only; xtensa needs the syscall block **and** the
flags constant.

**`$800` is MEASURED, not read off a table or taken from a comment.** Under
`qemu-xtensa -strace`, mmap2 with flags `$800` alone is decoded by qemu as
`MAP_ANONYMOUS` and returns EINVAL (no `MAP_PRIVATE`/`MAP_SHARED`); `$802` is
decoded as `MAP_PRIVATE|MAP_ANONYMOUS` and maps; `$22` is decoded as
`MAP_PRIVATE|0x20` — `0x20` is not a named flag on this target — and returns
EBADF, mapping fd `-1`. That is qemu's own flag decoder naming the bit,
independent of `builtinheap.pas:971`'s comment, which had been the only source.

**Scope of that measurement (frankS):** qemu's decoder is qemu's, not the
kernel's — but for this claim qemu *is* the right authority rather than a weaker
one, because hosted xtensa runs under qemu-user, so it is the execution target
for the profile where `PalBackendMmapAnon` and the thread-stack mmap actually
run. Read it as **measured under qemu-xtensa 10.2.1, the execution target for
the hosted profile** — not as a claim about silicon. The bare/ESP profile never
reaches mmap, so nothing there depends on it.

# Re-measured 2026-09-23 (frank) — half the work is done and the trap is defused

Summary rewritten. Both load-bearing claims in the old one had gone stale, in
the direction that OVERSTATES the work and misreads its urgency.

**riscv32 has a coswitch.** `coroutine_emit.inc` has arms for x86-64, i386,
aarch64, arm32 and **riscv32**, each setting `CoSwitchAddr`; the riscv32 one
landed in `fc70d0cbe`. Verified from the code and then from behaviour rather
than from either summary:

| target | `--emit-obj test/lib_asyncnet6.pas` |
| --- | --- |
| `esp32c3` | ok (649 procs) |
| `riscv32` | ok (649 procs) |
| `xtensa` | `error: coroutines are not implemented for target xtensa` |

Since **esp32c3 is riscv32** and every ESP example in the tree is a -c3,
coroutines and async work today on the target we actually exercise. The hole is
esp32/esp32s2/esp32s3 — the xtensa parts.

**And the silence is gone, which is what this ticket was really about.** The
body below is written around a *trap*: a silent fall-through that would turn
into "six programs stop erroring and start jumping into code that was never
emitted" the moment a syscall block appeared. There is now a loud refusal in
the way, so acquiring a syscall block cannot spring anything. This is a feature
gap, not an armed trap, and it should be ranked as one.

**What would make it a trap again** — stated as a mechanism so it does not
decay the way the old summary did: the refusal at `coroutine_emit.inc`'s tail
being removed or routed around without an xtensa arm landing in the same
commit. Nothing about a syscall table matters any more.

Read the sections below as the ORIGINAL 2026-09 report, not as current state.

---

# Landed 2026-09-24 (frank) — Call0, all three parts, one commit

**Read the sections above as the original report.** Two things in them are now
stale and are left in place: the syscall table's `timerfd_settime 313` row is
right but incomplete (see below), and *"The three parts, all of which must land
together"* is satisfied rather than pending.

## What the precondition check found first, because it nearly stopped this

Before writing any code I checked whether the six test rows could even RUN on
hosted xtensa, having just filed
[[bug-a-xtensa-emits-muluh-for-an-integer-multiply-and-no-stock-qemu-core-implements-it]]
— five of the six print integers, and integer formatting SIGILLs there. **The
answer was that `--xtensa-soft-mulhigh` has shipped all along**, which closed
that ticket and cleared this one's precondition in the same measurement. Had I
believed my own ticket I would have concluded this work was unverifiable and
parked it.

## The scope, and why Call0 alone is not half a job

`XtensaABI` defaults to `XTENSA_ABI_CALL0` (compiler.pas) and **only an explicit
`--xtensa-abi=windowed` moves it**. Measured, because a Makefile comment in this
tree claimed the opposite and was corrected in this commit: a flagless xtensa
build is **byte-identical** to `--xtensa-abi=call0` and **differs** from
`--xtensa-abi=windowed`. So Call0 is what every xtensa and esp32s3 build gets
unless asked otherwise, and the practical hole is closed. Windowed is
[[feature-a-a-windowed-abi-coswitch-for-xtensa]], sequenced as this body asks.

## Part 1 — the stub and the lowering, and why they are one commit

`coroutine_emit.inc` gains an xtensa Call0 arm; `ir_codegen_xtensa.inc` gains
`IR_COSWITCH`. **Separately, either one is a live miscompile**: a lowering with
no stub calls `CoSwitchAddr = 0`, which is offset 0 of `.text` — the program
entry — reached from inside user code, so it hangs or re-enters rather than
diagnosing. The 2026-08-31 note in `coroutine_emit.inc` predicted exactly this
("give riscv32 one without adding a stub arm here and the downstream guard
disappears"), and that note's `else` is now a fail-closed default for a target
that does not exist yet, with the prediction restated for the next backend.

**Frame: 16 bytes — exc_top, a15, a0, pad.** Three slots, and **the authority is
not the ABI, it is `exception_emit.inc`**: the xtensa Call0 jmpbuf this compiler
ships saves exactly `(a15, sp, a0)`. Call0's *nominal* callee-saved set is
a12–a15, and this backend treats a12/a13 as expression scratch. A switch saving
more than the jmpbuf would claim a guarantee the exception runtime does not
make; saving less would break both.

**Two things riscv32's arm does not need.** The entry is `nop`-padded to 4 bytes
because a `call0` target must be 4-aligned — Call0 encodes the low two bits as
zero, so an unaligned entry silently enters at a *different address* rather than
faulting. And the `BSS_EXC_TOP` address comes from the literal-pool idiom
(`XtensaEmitLitHeader` + `l32r`) because xtensa has no PC-relative add.

## Part 2 — `scheduler.pas`, and every number measured by NAME

One probe program under `qemu-xtensa -strace`, which prints the **kernel's own
identity** for each number instead of my belief about it:

| | xtensa | how it would have gone wrong |
| --- | --- | --- |
| `gettid` | 127 | in an abandoned range (118 exit, 119 exit_group, 124 tkill) |
| `epoll_create1` / `_ctl` / `_wait` | 275 / 19 / 18 | it has a real `epoll_wait`, so it takes the **x86** arm, not riscv32's `pwait` |
| `fcntl` / `read` / `close` | 67 / 12 / 9 | — |
| `timerfd_create` / `_settime` | 312 / 313 | **NOT time64** — see below |
| `mmap` / `mprotect` / `munmap` | 80 (mmap2) / 82 / 81 | asm-generic **222 is `Unknown syscall`**, and **64 is `utime`**, not mmap2 |
| `exit_group` | 119 | confirmed twice, by name and by the process really leaving rc=7 |

**The time64 row is the one that would have been silently wrong.** Both xtensa
and riscv32 are 32-bit ESP targets, so copying riscv32's block is the obvious
move — and riscv32 is time64-only, needing `timerfd_settime64(411)` and a 64-bit
itimerspec. On xtensa `timerfd_settime(313)` answers **EFAULT** (it exists and
tried to read the pointer) while **410 is `Unknown syscall`**. So xtensa
deliberately does **not** get `SCHED_TIME64`. This is precisely the failure the
file's own riscv32 note warns about: a number from the wrong table is not a
compile error, it is a different syscall at runtime.

**And the `palthread.pas` landmine above has a SIBLING in this file**, found by
looking for it rather than by anything failing: `scheduler.pas` had
`MAP_ANON_PRIV = $22` outside the arch split, used to map every coroutine stack.
Now split, xtensa `$802`. **The wrong value does not fail loudly** — `$22`
decodes as `MAP_PRIVATE|0x20`, the kernel takes fd −1 literally and returns
EBADF, `mapBase > 0` is False, and the code falls back to `GetMem`. The
coroutine then runs on an **unguarded heap stack**, silently, which is the one
outcome the guard-page machinery exists to prevent. Measured on this file's exact
call shape, with the landmine's warning against "tidying" riscv32 to `$802`
carried into the code comment.

The priming is byte-for-byte riscv32's, deliberately, so it is one shape with two
register names — with a comment saying so, because two identical arms read as a
copy-paste mistake.

## Part 3 — the rows, and what makes them non-vacuous

Six rows in `test-xtensa`, asserted **against the x86-64 build of the same
source** rather than literal strings: the pair is then a RELATION carrying no
per-target constant, so a row cannot encode an xtensa-specific wrong answer as
its own expectation. Plus an `esp32s3`-vs-`esp32c3` `lib_asyncnet6 --emit-obj`
parity row, which is the ESP-facing point of all this, and a negative control
asserting the windowed refusal **by name**.

**All six MATCH the x86-64 oracle** under `qemu-xtensa`. `esp32s3` now builds
`lib_asyncnet6` (685 procs) where before it stopped at `uses scheduler`.

**Positive control, drawn from the population:** perturbing the priming by one
slot — `@CoStart` to `top+4` instead of `top+8` — makes `test_scheduler` and
`test_asyncecho` **segfault** under qemu. So the rows exercise the CoSwitch
contract rather than merely importing the unit. riscv32's four comparable rows
were re-run unchanged and still match, so the shared-file edits did not move it.

**One guard was born unable to pass and was caught by running it**: the windowed
control first redirected `2>` by analogy with other refusal rows in the Makefile,
and **pascal26 writes diagnostics to STDOUT** — the `.err` file came back 0 bytes
and the `grep` failed while the refusal worked perfectly. The other rows get away
with `2>/dev/null` because they only assert a nonzero exit and never read the
text. Fixed to `>`, and the grep was then checked to discriminate (a
deliberately wrong pattern returns 1).

## What is NOT claimed

Hosted xtensa under `qemu-xtensa`, Call0, with `--xtensa-soft-mulhigh` — so
arithmetic is not bit-identical to silicon and any numeric verdict from these
rows must name the flag. The `esp32s3` row is a **compile** assertion; nothing
here ran on an xtensa ESP part. Windowed is untouched and refused.

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 1dd37bbb4d.
