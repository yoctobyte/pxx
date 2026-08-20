---
track: A
prio: 50
type: feature
blocked-by: []
summary: "The runtime has no thread-local storage: PXX_CLONE_THREAD is $350F00, which omits CLONE_SETTLS, so every thread shares the parent's fs base. Nothing per-thread is reachable more cheaply than a gettid syscall, which is what blocks per-thread heap arenas — the remaining half of feature-threadsafe-heap-optimize — and any other per-thread fast path."
status: done
owner: claude-A
---

# Thread-local storage: threads share one `fs` base

- **Track A** (PAL / thread creation — `lib/rtl/palthread.pas`, plus whatever
  sets the TLS block up per thread).
- Found 2026-08-20 while doing the lock half of
  [[feature-threadsafe-heap-optimize]], which is where it bites first.

## The finding

`lib/rtl/palthread.pas` creates threads with

```pascal
PXX_CLONE_THREAD = $350F00;
```

Decoded, that is `CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND |
CLONE_THREAD | CLONE_SYSVSEM | CLONE_PARENT_SETTID | CLONE_CHILD_CLEARTID`.
**`CLONE_SETTLS` ($80000) is not among them.** So every thread inherits the
parent's `fs` base, and an `fs:`-relative slot is the *same* memory in every
thread — worse than absent, because it looks like TLS and silently aliases.

## Why it matters beyond one ticket

Anything wanting per-thread state today has exactly two options, and both are
bad:

1. **`gettid` and index a table** — a syscall per access. Acceptable at
   statement granularity (the `--threadsafe` I/O lock already does this per I/O
   statement) and hopeless on an allocator fast path, which is the point.
2. **Don't have per-thread state**, which is where the runtime is now.

Concretely blocked:

- **Per-thread heap arenas / a thread-local free-list magazine** — the remaining
  half of [[feature-threadsafe-heap-optimize]]. Its lock half landed and removed
  the contention *overhead* (−26/−32/−29% at 2/4/8 threads, see
  `benchmarks/2026-08-20-threadsafe-heap-lock.md`), but the allocator still
  serialises on one global lock and no cheap per-thread cache is reachable to
  fix that.
- Any future per-thread errno, exception-stack, or RNG state.

## Shape of the work

Set `CLONE_SETTLS` and pass a per-thread TLS block as clone's `tls` argument,
allocated alongside the thread's stack in `palthread`. Per-arch:

- **x86-64** — clone's `tls` arg sets the `fs` base directly; the block wants
  the usual self-pointer at offset 0 so `mov rax, fs:[0]` yields its own address.
- **aarch64** — `tpidr_el0`.
- **i386** — the awkward one: clone takes a `struct user_desc*`, not a raw base.
- **arm32** — `set_tls` / `tpidruro`.

Then a compiler-side accessor so runtime code can reach a slot without a
syscall.

**Do not derive per-thread identity from the stack pointer** as a shortcut. It
works until a thread's stack is reused or a handler runs on the sigaltstack —
where SP is deliberately somewhere else entirely, which
[[feature-signal-siginfo-ucontext]] item 3 just made a normal occurrence.

## Gate

A per-thread slot that is genuinely distinct per thread under contention (the
`test_thread_heap` shape: N threads write a unique tag and read it back),
existing thread suite green, `--threadsafe` still correct on every target that
accepts it, self-host byte-identical.

## 2026-08-20 — RESOLVED, and the prescribed remedy was the wrong one

### The finding held; the fix in "Shape of the work" did not

The premise above is correct and is now **measured** rather than read off a
constant: delete the per-thread install from `test/test_tls_base.pas` and four
threads report **~39000 tag mismatches** against each other, because clone does
not reset `fs` and every child reads the parent's block.

What did not survive contact is the prescription — *"Set `CLONE_SETTLS` and pass
a per-thread TLS block as clone's `tls` argument"*. That would have meant a sixth
`__pxxclone` argument, four `IR_CLONE` lowerings, four hand-emitted stub legs, a
`user_desc` struct on i386, and the two other frontends' copies of the intrinsic.

**`arch_prctl(ARCH_SET_FS)` acts on the CALLING thread.** So a thread installs its
own block as its first act and `clone` is not involved at all. Installing needs
**no compiler support whatsoever** — it is `__pxxrawsyscall(158, $1002, blk, ...)`,
an ordinary syscall through machinery that already exists.

Only the READ side needed a compiler, and only because the x86-64 `fs` base is
not readable as a register (`rdfsbase` requires `CR4.FSGSBASE`, not guaranteed).
So the whole change is one no-operand intrinsic:

- `AN_TLSBASE` (96) / `IR_TLSBASE` (73), modelled on `AN_FRAME`/`IR_FRAME`.
- x86-64 codegen: `mov rax, fs:[0]` — nine bytes, one instruction.
- Pascal frontend: `__pxxTlsBase`, tyPointer, refused on the other four targets.

Net: **~40 lines across four files, one backend touched**, versus the multi-arch
clone surgery the ticket asked for. Same discipline as
`root-cause-over-microfix.md`, running the other way for once — the ticket named
a plausible mechanism and the smaller one was real.

### The convention, and the trap in it

**Slot 0 of the block holds the block's own address** (what glibc and musl do,
for exactly this reason). `__pxxTlsBase` is deliberately **read-only and
base-only**: with the self-pointer in place, ordinary pointer arithmetic reaches
every future per-thread field — arena, errno, exception stack, RNG — so there is
never an intrinsic per field.

The trap the ticket warned about is NOT removed by this, it is relocated:
**installing is mandatory, and belongs in the launcher before user code runs.**
A thread that skips it does not read a null base you can test for — it reads the
*parent's* block, i.e. the aliasing bug wearing a pointer that looks fine. The
negative run above is that failure mode, deliberately provoked.

The "do not derive per-thread identity from the stack pointer" warning stands and
was not needed: nothing here looks at SP.

### x86-64 only, deliberately

aarch64 (`tpidr_el0`), arm32 (`tpidruro`) and i386 (`gs`) all have a *readable*
thread register, but this runtime has no path that *sets* one — i386 in
particular wants a `struct user_desc` rather than a raw base. So the frontend
errors there at compile time, naming this ticket, rather than answering with the
parent's block. Same call as `__pxxSigNum` and the `si_code` slice: a plausible
wrong pointer is worse than a compile error, and threading is x86-64-only today
anyway (the clone stub exists on four arches but `--threadsafe` gates the rest).

### Test

`test/test_tls_base.pas`, wired into `test-threads`. Four threads, each installs
its own block and re-reads its tag 20000× while the others churn. Four distinct
assertions, each catching a different way to be wrong: blocks distinct (the
aliasing bug), the parent's tag intact after the joins (children must not disturb
it), `__pxxTlsBase` = the installed address (a wrong `fs:[0]` encoding would still
return *something*), and the churn loop (a shared base can pass a post-join
snapshot and still tear under contention). Run 10× consecutively, 0 errors —
a threading change earns repetition rather than one pass. `pinned` rejects the
program outright (`undefined variable (__pxxTlsBase)`), so it bites.

### What this unblocks, and what is left

[[feature-threadsafe-heap-optimize]] moved to `blocked/` on this ticket; the
primitive it was waiting for now exists, so its per-thread-arena half is
unblocked. But the remaining work there is **`lib/rtl`** — `palthreadobj`'s
launcher installing a block per `TThread`, and the allocator magazine itself —
which is **Track B's file-lane**, not A's. This ticket delivers the compiler
primitive and stops at the lane boundary.

Also still open and *not* addressed here:
[[audit-shared-global-reentrancy-thread-safety]] (`BSS_EXC_TOP` and friends) now
has a mechanism available, but moving those globals into TLS is its own ticket —
every one of them is read on paths that run before any install could have
happened, which is the same ordering problem in a harder place.

Docs: `devdocs/dev/threading.md` gained a "Thread-local storage (x86-64)" section.

### Gate

`make compiler/pascal26` (byte-identical fixedpoint, converged in 1 round) +
`tools/gate.sh quick` + `test_tls_base` ×10 + the negative variant.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
