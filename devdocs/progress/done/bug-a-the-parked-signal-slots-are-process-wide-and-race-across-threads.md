---
slug: bug-a-the-parked-signal-slots-are-process-wide-and-race-across-threads
track: A
prio: 55
type: bug
status: done
owner: frankS
blocked-by: []
summary: "FIXED 2026-08-31: the four dispatch-parked fields moved into per-thread TLS slots (TLS_SLOT_SIG_CODE.._NUM) behind ONE accessor that picks the base. Reproduced independently at 75875 wrong answers in 400000 deliveries; 0 after, three runs. The branch is by TARGET and TlsMainInstalled, NOT --threadsafe -- `always TLS` was not available, since only x86-64 has a block. Threads that INHERITED a block (glibc pthread_create) still share it: strictly better, never worse, not complete."
---

# The parked signal slots are process-wide and race across threads

- **Found:** 2026-08-31 by frankA, finishing item 2 of
  [[feature-signal-siginfo-ucontext]] — the item asked to *define* the
  `--threadsafe` interaction, and this is the part of the definition that is a
  defect rather than a property.

## Measured

Two threads, each `tkill`-ing **itself** 200000 times with its own signal
(SIGUSR1 on main, SIGUSR2 on the worker). The handler asks which thread it is on
and compares `__pxxSigNum` against the signal that thread sends itself:

```
two threads:      hitsA=200000  hitsB=200000  mismatch=91104   (~23%)
one thread:       hitsA=200000  hitsB=0       mismatch=0
```

Same binary, same handler, same counters — the second run just never starts the
worker. **Zero against ninety-one thousand** is the whole argument; the mismatch
counter is itself non-atomic, so treat 91104 as approximate and 0 as exact.

Nesting is ruled out as an alternative explanation: a handler runs with its own
signal masked (no `SA_NODEFER`), and each signal is directed at exactly one
thread, so nothing re-enters within a thread.

## Why

`BSS_SIG_NUM` / `_CODE` / `_ADDR` / `_CTX` are single process-wide slots
(`EnsureSignalBss`, `ir_codegen.inc`). The dispatch stub writes them from the
kernel's argument registers, then calls the hook. With two threads in the stub
at once, the second store lands before the first hook reads.

The window is small and the rate is 23%, which is the bad kind of bug: rare
enough to pass every existing test, common enough to hit production.

## What it breaks

[[feature-b-fpc-signal-compat-unit]] — item 4's RTL half — is a table indexed by
`__pxxSigNum`. Under threads it dispatches to the WRONG registered handler,
silently. The hook ABI is parameterless by design, so the slot is the *only*
carrier; there is no second source to cross-check against.

## The fix, and the decision inside it

Per-thread storage. pxx already has TLS (`BSS_TLS_MAIN`, carved per thread under
`--threadsafe`), so the mechanism exists. The question this ticket does NOT
decide:

- **always TLS**, which costs every single-threaded program a TLS access on
  four intrinsics that are read at most once per signal; or
- **TLS only under `--threadsafe`**, which means the dispatch stub and the four
  intrinsic lowerings each grow a mode branch — two shapes for one concept, the
  smell `devdocs/dev/normalise-dont-special-case.md` names.

Recommendation: **always TLS**. These are read once per delivered signal, so the
cost is unmeasurable, and it keeps one code path. But it is a real fork and it
belongs to whoever owns the TLS layout.

## Note for whoever takes it

The alt stack (`BSS_SIG_ALTSTK`) has the SAME shape and is NOT covered here: one
process-wide alt stack shared by every thread means two concurrent
stack-overflow faults use the same buffer. Not measured — a second finding, on
the same construction, and worth checking in the same pass.

## 2026-08-31 — FIXED. And two of this ticket's own premises were wrong

### What shipped

`TLS_SLOT_SIG_CODE` / `_ADDR` / `_CTX` / `_NUM` (slots 4..7), filled by the
dispatch stub and read by `__pxxSigCode/_Addr/_Context/_Num`, the
`--fpc-float-errors` decoder and the `--fpc-mem-errors` decoder.

**One decision site, not five.** `EnsureSignalBss` now allocates the four BSS
slots contiguously in the same order as the TLS slots *and asserts it*, so every
writer and reader addresses a field as `base + (BSS_SIG_x - BSS_SIG_CODE)` — one
offset expression, correct in both modes. `EmitSigGroupBaseX64` is the only
place that knows which base. That is what dissolves the "two shapes for one
concept" worry in the section above: the smell was two *decision* sites, not two
behaviours.

Reproduced independently before touching anything, with
`test/test_signal_num_threads_race.pas`: **75875** mismatches in 400000
deliveries, **0** in the single-threaded phase of the same binary. After: **0
and 0**, three runs. `--fpc-mem-errors` (five fault shapes) and
`--fpc-float-errors` (div/ovf/inv) still report the right FPC codes, which also
proves the TLS read works from a **SA_ONSTACK handler** — see below.

### Premise 1 that was wrong: "always TLS"

`EmitTlsMainInstall` is x86-64-only and cloned threads get their block from the
x86-64 clone stub, so on i386/aarch64/arm32/riscv32 **there is no block to
read** and those targets keep the process-wide group. And with
`--emit-obj`/`--shared` nothing installed a base, where `mov rax, gs:[0]` does
not return 0 — it **faults**. So the real condition is by TARGET and by
`TlsMainInstalled`; `--threadsafe` never enters it. Both are known at emission,
so no runtime branch exists anywhere. (frankA agreed and asked for the section
to be overwritten rather than worked around: *"a recommendation that isn't
available isn't a fork arm"*.)

### Premise 2 that was wrong, and it is the one worth carrying: THE BOUNDS CHECK CANNOT BE THE VALIDATOR HERE

The obvious move was to reuse the `stackLow <= rsp < stackHigh` test from
`feature-a-io-lock-owner-from-tls-not-gettid` to reject an inherited block. It
would have been **useless in a way that reports success**: a `SA_ONSTACK`
handler runs with `rsp` on the **sigaltstack**, i.e. outside its own thread's
bounds, so the check answers "not my block" on *every* delivery, the writer and
the reader agree, and the code quietly does exactly what it did before the fix.
A guard whose failure mode is a **silent fallback to the pre-fix behaviour** is
worse than one that errors, because nothing distinguishes "working" from
"always missing". The signal fields therefore read `gs:[0]` unvalidated: writer
and reader are the same thread with the same base, so they always agree.

### The limit, stated because it is invisible from the code

A thread that **inherited** its block — glibc `pthread_create`, a callback from
a C library — shares it with its creator and still races. Threads pxx created
have their own. Strictly better than process-wide, never worse, and not
complete; no content check can close it, for the reason
`feature-a-io-lock-owner-from-tls-not-gettid` records.

### The alt stack, which frankA flagged: measured, and it is a different bug

He guessed one shared buffer with two faults colliding. The measurement says the
worker has **no alt stack at all** (`sp=0 flags=SS_DISABLE size=0`), because
`sigaltstack(2)` is per-thread and only `SetSignalHandler` registers one. Same
binary, one argument apart: an overflow on main enters the handler and exits 7;
on a cloned worker it exits **139** with no output.
Filed as
[[bug-a-a-cloned-thread-has-no-sigaltstack-so-its-stack-overflow-is-unhandleable]].

### Not touched, deliberately

`BSS_EXC_OBJ` / `BSS_EXC_ADDR` are process-wide too and share the `IR_EXC_STORE`
reader. Whether an exception in flight on two threads at once races the same way
is a separate question with a separate repro, and guessing it here would be the
same mistake as premise 1.

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.
