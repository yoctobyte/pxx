---
track: A
prio: 50
type: feature
blocked-by: []
summary: "The runtime has no thread-local storage: PXX_CLONE_THREAD is $350F00, which omits CLONE_SETTLS, so every thread shares the parent's fs base. Nothing per-thread is reachable more cheaply than a gettid syscall, which is what blocks per-thread heap arenas — the remaining half of feature-threadsafe-heap-optimize — and any other per-thread fast path."
status: backlog
owner: ""
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
