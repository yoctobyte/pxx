---
track: A
summary: "Finish --rtl-libc: convert the C/Rust/Zig frontend syscall sites, and test the thread errno hazard the raw clone stub creates"
type: feature
prio: 40
---

# Finish `--rtl-libc` — the frontend sites, and the thread/errno hazard

- **Type:** feature (Track A). Follow-up to `feature-port-rtl-over-libc`, which
  landed increments 1–3 and is resolved.
- **Owner:** unassigned
- **Opened:** 2026-08-30, splitting the remainder out of the parent ticket so the
  parent's delivered scope is not held open by work nobody is doing.

## Where the parent left it

`--rtl-libc` works on x86-64 for Pascal programs: residual kernel-entry
instructions **73 → 1**, that one being the `rt_sigreturn` restorer, which must
stay raw. Verified across hello, the div0 stub, SIGTERM delivery,
`test_multithreading.pas` and `test_io_checks_iplus.pas` (the errno path), each
identical to the default build. Default codegen is byte-identical to the pinned
compiler's output.

Two pieces were deliberately not done.

## 1. The frontend syscall sites

`cparser.inc`, `eparser.inc`, `rparser.inc` and `zparser.inc` each emit a raw
`EmitB($0F); EmitB($05)`. No Pascal program reaches them, so they were neither
converted nor tested.

The conversion itself should be small — route them through `EmitSyscall` (or
`x64_syscall`, which now funnels every compiler-generated kernel entry). **The
work is the test**, not the edit: a C/Rust/Zig program in `--rtl-libc` mode that
actually executes the converted site.

**Before converting any of them, decide per site whether it is `syscall` or
`syscall_raw`.** The rule from the parent ticket: anything whose contract is the
machine state *at the instruction* — rsp-relative, or non-returning — must be
`syscall_raw`. Getting this wrong is not a compile error and not a crash at the
site; `rt_sigreturn` presented as a SIGSEGV on the first delivered signal, in a
build whose syscall count, hello-world and div0 path were all perfect.

## 2. The thread errno hazard — reasoned, unobserved, and it has a precise trigger

`thread_emit.inc`'s `clone` child stub is raw by design (the child runs on a
fresh stack). A consequence: a pxx-created thread **inherits the parent's FS
base**. The thunk's errno fixup calls libc's `__errno_location`, which is
FS-relative — so on a pxx thread it resolves to the **main thread's** errno slot.

Within a single thread this is invisible: the write goes to a valid address and
the immediate read-back is correct. The symptom is cross-thread — a worker's
failing syscall silently overwriting another thread's `errno`.

`test_multithreading.pas` passes under `--rtl-libc` and does **not** refute
this: every syscall in it succeeds, so the fixup never fires.

**Trigger to build:** a pxx-created thread performing a *failing* syscall, with
the main thread checking its own `errno` is unchanged across it. That test is
the first thing to write here, and it decides whether this is a bug or a
non-issue. Do not convert the frontend sites and declare the feature done
without it — the population that would expose this is exactly the population
nobody has run.

## 3. `-O3` is refused, loudly

`EmitSyscall` errors out under `-O3`: a shared out-of-line thunk cannot carry
`-O3`'s per-function float-register pool (`FxSaveBase` is frame-relative), so
the pool save/restore would store into whichever caller jumped in, at another
function's offset. Lifting it means saving the pool at the **call site** rather
than in the thunk. Optional, and a separate piece of work from either of the
above.

## Gate

`make compiler/pascal26` + the repro, per CLAUDE.md. Plus the two checks the
parent ticket established as non-negotiable for this feature:

1. **Default codegen byte-identical to the pinned compiler's output** — not just
   a self-host fixedpoint. A uniformly-wrong compiler reproduces itself
   perfectly, so the fixedpoint cannot see a change to default emission.
2. **A test that exercises the converted path at runtime**, not a syscall count.
   The count answers "does a `syscall` instruction remain", which is true and is
   not the question.
