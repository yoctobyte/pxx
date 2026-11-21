---
slug: feature-a-crtl-sigaction-cannot-honour-sa-siginfo-because-the-thread-block-has-no-slot-for-it
track: A
prio: 45
type: feature
status: backlog
owner: ""
created: 2026-11-21
found-by: claude-pxx (toybox suite, timeout rows)
tags: [crtl, signals, tls, toybox]
blocked-by: []
summary: "OWNER 2026-11-21: go ahead (renumber the thread block, option 1, after the literal-offset census); targets with no signal runtime (ESP, Windows) should not pay for the slot if that can be done smartly -- not a hard requirement for 16 bytes. crtl's sigaction refuses SA_SIGINFO with EINVAL, by design: the hook into pxx's signal runtime is one-argument. toybox `timeout` installs its SIGCHLD handler with SA_SIGINFO and reads si_status/si_code, so all 14 of its suite rows fail (`xsignal 17: Invalid argument`, exit 125); toybox sh uses it too. The emitted dispatch stub already HAS the kernel's siginfo pointer (it reads si_code and si_addr out of it into the parked slots) -- what is missing is one more parked slot to carry the pointer to the C hook. The per-thread block has none free: slots 0-15 are packed and the heap lists start at 16, and the signal four must stay contiguous. So the fix is a thread-block layout change, not a crtl change."
---

# crtl's sigaction cannot honour SA_SIGINFO

## What fails

toybox `timeout` (14 suite rows) does

```c
static void handler(int sig, siginfo_t *si)
{
  TT.rc = si->si_status + ((si->si_code!=CLD_EXITED)<<7);
  siglongjmp(TT.sj, 1);
}
...
xsignal_flags(SIGCHLD, handler, SA_NOCLDSTOP|SA_SIGINFO);
```

and crtl answers EINVAL (lib/crtl/src/signal.c, `sigaction`). Measured with a
probe: every `SA_SIGINFO` install fails, on any signal; every other flag is
accepted. glibc accepts all of them.

The refusal is honest and documented. Accepting the flag while calling the
handler with one argument would hand it two garbage pointers in signal
context. A handler that reads `si_status` needs the real siginfo; a fake one
built from the parked `si_code`/`si_addr` would give the wrong status.

## What already exists

- The kernel enters pxx's emitted dispatch stub with `(sig, siginfo *,
  ucontext *)`, because the runtime installs with SA_SIGINFO on every hosted
  target.
- The stub parks `si_code`, `si_addr`, the ucontext pointer and the signal
  number (BSS_SIG_CODE/ADDR/CTX/NUM, or TLS_SLOT_SIG_* under
  `--threadsafe`), and `__pxxSigCode`/`__pxxSigAddr`/`__pxxSigContext`/
  `__pxxSigNum` read them.
- crtl's C hook (`CSigTrampoline`, lib/rtl/pxxcio.pas) calls the C handler as
  `h(n)`.

So the siginfo pointer is in a register at the right moment and is thrown
away.

## Why it is not a small change

A fifth parked field, the siginfo pointer, is one store per backend (x86-64,
i386, arm32, aarch64, riscv32, xtensa). Then `__pxxSigInfo` reads it, and the
C hook calls `h(n, info, ctx)` for a handler installed with SA_SIGINFO.

But the fields are addressed as group base plus offset, in both BSS and the
per-thread block, and EnsureSignalBss asserts their contiguity. In the thread
block, slot 8 (`TLS_SLOT_EXC_TOP`) follows SIG_NUM, and slots 0-15 are all
taken (TLS_SLOT_FIRST_FREE = 16 = TLS_SLOT_HEAP_MAG). The options as seen
from here, not measured:

1. **Renumber the thread block:** SIG_INFO = 8, everything after it +1, the
   heap lists from 17. That is correct if every user names the constants. It
   needs a census of literal offsets in the backends and the clone stub first.
2. **Put SIG_INFO outside the group,** in its own slot taken from the free end,
   with its own accessor. The contiguity rule stays intact, at the cost of a
   second addressing path for one field.
3. **crtl installs its own kernel handler** for SA_SIGINFO, through
   rt_sigaction, with a restorer. That is a second signal mechanism beside the
   runtime's, which the runtime's comments argue against ("two surfaces over one
   mechanism, not two mechanisms").

Each touches the thread-block layout or the signal design, so this wants a
decision before code.

## Test that would close it

toybox's own `tests/timeout.test`, plus a crtl row: a SIGCHLD handler
installed with SA_SIGINFO reads `si_status` and `si_code` of a child that
exits 3, and of one killed by SIGKILL. The expected output comes from gcc.
Run it under `--threadsafe` too, where the slot is per thread.

## Owner, 2026-11-21

> for the signals, that's not such big issue, at least not on pc platforms.
> however, platforms without signals (esp, windows) should avoid wasting
> space. although i'm not worried about the last 16 bytes, but it's something
> to keep in mind if we can do that smart.

So: option 1 (renumber), census of literal slot offsets first. Where the
target has no signal runtime (TargetHasSignalRuntime false), the signal group
should cost nothing if the layout can allow it -- for instance by putting the
signal group LAST among the fixed slots, so a target without signals can end
the fixed area before it. Not a blocker if it cannot.
