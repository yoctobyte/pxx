---
slug: bug-a-the-parked-signal-slots-are-process-wide-and-race-across-threads
track: A
prio: 55
type: bug
status: working
owner: frankS
blocked-by: []
summary: "MEASURED: 91104 wrong answers in 400000 deliveries (~23%). `__pxxSigNum` / `__pxxSigCode` / `__pxxSigAddr` / `__pxxSigContext` read process-wide BSS slots that the dispatch stub writes. Under --threadsafe two threads taking signals concurrently clobber each other's parked values, so a handler reads a number belonging to the OTHER thread's signal. Single-threaded control on the same binary: 200000 deliveries, ZERO mismatches. This makes item 4's whole purpose -- an FPC-compatible `Signal(sig, handler)` dispatching on the number -- silently misroute under threads. The fix is per-thread storage, and the design question (always TLS, or only under --threadsafe) is why this is filed rather than fixed."
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
