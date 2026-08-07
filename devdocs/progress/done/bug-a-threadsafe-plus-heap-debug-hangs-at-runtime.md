---
track: A
prio: 40
type: bug
summary: "A program built with BOTH --threadsafe and -dPXX_HEAP_DEBUG hangs at runtime; either flag alone is fine. The two debugging modes the runtime offers cannot be combined, which is exactly when you would want both"
status: done
owner: claude-AN
---

# `--threadsafe` + `-dPXX_HEAP_DEBUG` hangs at runtime

- **Type:** bug (hang, debug tooling) — **Track A**
- **Found:** 2026-08-07, incidentally, while gating
  [[feature-a-managed-block-kind-word]].
- **Pre-existing** — the pinned binary hangs identically, so this predates the
  managed-block header change. Controlled, not assumed.

## Measured

```pascal
program ts1;
var s, t: AnsiString; i: Integer;
begin
  s := 'threadsafe';
  for i := 1 to 100 do s := s + '.';
  t := s;                 { share: refcount 2 }
  WriteLn(Length(s), ' ', Length(t));
  s := '';
  WriteLn(Length(t), ' survivor-ok');
end.
```

| build | result |
| --- | --- |
| `--threadsafe` | correct, exits 0 |
| `-dPXX_HEAP_DEBUG` | correct, exits 0 |
| `--threadsafe -dPXX_HEAP_DEBUG` | **compiles fine, then hangs** (killed at 60s) |
| same, on the PINNED binary | **hangs too** — pre-existing |

Compilation succeeds in every case; the hang is at run time.

## Why it is worth fixing despite the low priority

These are the runtime's two debugging modes, and the combination is precisely
the one a hard bug wants: a refcount problem that only appears under threading is
exactly what `PXX_HEAP_DEBUG`'s poison and quarantine exist to diagnose. Today
that combination is unavailable, and it fails by hanging rather than by saying
so — a session reaching for it would lose time to the tool before suspecting it.

## Not investigated

Whether it is the softlock (`PXX_TS_SOFTLOCK`) re-entering the heap lock from
inside a debug-path allocation, or the quarantine ring interacting with the
atomic refcount path. Both are guesses; measure before believing either. The
heap lock and the debug bookkeeping in `compiler/builtin/builtinheap.pas` are
the two places to look.

## Gate

Per-fix loop. A test that builds the repro above with both flags and asserts it
terminates with the right output — plus each flag alone, which must stay
correct.

## FIXED 2026-08-07 — a single-threaded self-deadlock on the heap spinlock

Both guesses in "Not investigated" were wrong-ish: it is neither the softlock
(x86-64 does not use `PXX_TS_SOFTLOCK`) nor the quarantine ring. Measured, not
reasoned:

1. `wait4` / `do_wait` on the first sample was a **mis-measurement** — `$!` after
   `cd X && ./prog &` captures a bash subshell, not the program. The real
   process is state **R**, busy-spinning. Worth remembering: check
   `/proc/<pid>/comm` before believing a sample.
2. Stepping the real process gives a four-instruction loop, and disassembling it
   from the LIVE process (the on-disk offsets kept mis-aligning) names it:

```
40012d: mov    $0x1,%eax
400132: lock xchg %eax,0x40cf40      ; take the heap lock
40013a: test   %eax,%eax
40013c: jne    0x40012d              ; already held -> spin
```

One thread, one lock, taken twice. The code right after the acquire is a string
RELEASE (`test %rax,%rax; je …; lock decq -0x10(%rax)`).

### The cycle

`EmitHeapFreeLocked` (ir_codegen.inc) calls `PXXFree` **from inside the locked
region** — its own header says so. Under `PXX_HEAP_DEBUG`, `PXXFree` ends with
`PXXDbgFlush`, and that routine declared a **managed local**, `msg: string`.
Finalizing that local on the way out enters the emitted string-release blob,
which takes the heap lock again. Deadlock.

`PXXDbgFlush`'s own header already required the lock to be released — but it
says *"the allocator lock"*, meaning the `PXX_TS_SOFTLOCK` spin variable, which
`PXXFree` does drop before calling it. On x86-64 the lock is the **hand-emitted**
one, which `PXXFree` cannot see or release. So the only rule that holds on every
target is that this routine must allocate **nothing**.

Confirmed by narrowing: an integer-only program was fine under both flags; any
program that frees a managed string hung.

### Fix

`PXXDbgFlush` no longer has a managed local. The four report texts are string
CONSTANTS indexed in place by a new `PXXDbgPutConst`, writing a byte at a time
exactly as before. Everything added sits inside `{$ifdef PXX_HEAP_DEBUG}`, so a
normal build is unchanged — which is why this needed **no re-pin**: the frozen
builtin the compiler links is byte-identical (gate GREEN on the first run).

### Measured, controlled against PINNED

| build | pinned | fixed |
| --- | --- | --- |
| `--threadsafe` | ok | ok |
| `-dPXX_HEAP_DEBUG` | ok | ok |
| `--threadsafe -dPXX_HEAP_DEBUG` | **HANG** | ok |

And the reporting still works, which is the half a "fix" could silently break:
a deliberate double free prints
`pxx-heap: DOUBLE FREE of 0x…` under plain `-dPXX_HEAP_DEBUG` **and** under the
combination — the pinned binary prints the identical text for the plain build,
so the message is unchanged and only the deadlock is gone.

### Test

`test/test_threadsafe_heap_debug_combo.pas`, built THREE ways by the Makefile
(each flag alone and both together) and required to produce identical output, so
a future fix cannot pass by disabling either mode. Managed-string work
throughout, since an integer-only program never reproduced.

### Gate

`make fpc-check` byte-identical, self-host fixedpoint, `tools/gate.sh quick`
GREEN (no re-pin required, see above).

## Log
- 2026-08-07 — resolved, commit PENDING-COMMIT.
