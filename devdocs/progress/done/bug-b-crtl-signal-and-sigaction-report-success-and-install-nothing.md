---
slug: bug-b-crtl-signal-and-sigaction-report-success-and-install-nothing
title: "crtl's signal() and sigaction() return success and install no handler, while the runtime next door has working handlers"
track: B
prio: 70
type: bug
status: done
created: 2026-09-04
found-by: franks-ab
owner: ""
blocked-by: []
summary: "**FIXED 2026-09-04. signal(), sigaction() and raise() really install and really fire, byte-identical to gcc/glibc on x86-64, i386, arm32 and aarch64.** The reach was the right shape and needed no second rt_sigaction: crtl calls `__pxx_c_signal` (lib/rtl/pxxcio.pas), which stores the C function pointer in a table and installs ONE parameterless trampoline through the compiler's existing signal runtime, reading `__pxxSigNum` for the number -- the same mechanism lib/rtl/signals.pas uses for the FPC surface, so there are now two SURFACES over one mechanism rather than two mechanisms. What is not honoured is REFUSED, not ignored: SA_SIGINFO gives EINVAL (the hook ABI passes one argument, so a three-argument handler would get two garbage ones in signal context), and sa_mask is accepted-and-not-installed, recorded rather than hidden because refusing it would reject most real callers over a property few depend on. Builds with no signal runtime (ESP, windowed xtensa, --no-signals) answer -1/ENOSYS from the bridge's guarded else-arm -- never 0, which was the entire defect. New test/c_crtl_signal_dispositions.c, 9 rows, EVERY ONE asserting the handler's EFFECT and never the return code, because rc=0 is exactly what the broken version produced. Its positive control needs no revert: --no-signals takes the refusing arm and all nine rows move. Row 10 of c_crtl_busybox_394_gaps.c strengthened from pause-blocks to pause-blocks AND a handler wakes it with -1/EINTR, as this ticket asked. Two things came out of the work: a compiler define PXX_HAS_SIGNALS keyed on TargetHasSignalRuntime (so an RTL guard can ask the capability instead of the arch, which is how signals.pas went stale for four days), and bug-b-crtl-waitpid-returns-enosys-on-riscv32-so-no-program-can-reap-a-child, which is why the cross rows stop at three targets and say so. ORIGINAL REPORT: MEASURED on pinned v403. A C program calling sigaction() gets rc=0 and errno untouched, and the handler never runs: lib/crtl/src/signal.c:127 is `(void)sig; (void)act; (void)oact; return 0;`. signal() is the same. The failure is SILENT and the success is the problem -- a caller that checks the documented error path sees none, so the program runs with the kernel's DEFAULT disposition and dies on the first SIGALRM/SIGINT/SIGCHLD it was expecting to handle. Measured: sigaction(SIGALRM), alarm(1), pause() -> `Alarm clock`, process terminated, where glibc runs the handler. This is DOCUMENTED in that file's own header ('link-only stubs ... no rt_sigaction PAL bridge yet') but has no ticket, and the premise in that sentence has since expired: lib/rtl/signals.pas HAS rt_sigaction with a restorer, an altstack and siginfo/ucontext, all landed and tested (feature-signal-handlers, feature-signal-siginfo-ucontext, test_signal_altstack.pas). So the machinery exists one lane over and crtl does not reach it. Bounds every signal-using C program: busybox init, hush, syslogd, crond and the whole job-control path install handlers, and the 853-case corpus cannot see it because those cases only run `applet --help`."
---

# crtl signal handlers: installed successfully, never fire

## The measurement

```
                      gcc/glibc      pxx pinned v403
sigaction(SIGALRM)    rc=0 errno=0   rc=0 errno=0      <- identical, and one is a lie
signal(SIGUSR1)       ok             ok
raise(SIGALRM)        handler ran    handler did NOT run
sigaction+alarm+pause handler ran    "Alarm clock", process TERMINATED
```

`lib/crtl/src/signal.c:127`

    int sigaction(int sig, const struct sigaction *act, struct sigaction *oact) {
      (void)sig; (void)act; (void)oact;
      return 0;
    }

## Why `return 0` is the defect and not the stub

A stub that returned -1/ENOSYS would be a missing feature: every caller that
checks `if (sigaction(...) < 0)` — which is what careful code does — would find
out. Returning 0 converts it into a **wrong answer**, and the program proceeds
on the strength of it. The process then runs with the kernel's default
disposition, so the first signal it was written to handle **terminates it**,
far from the call that reported success.

This is the same shape as an expected value colliding with a failure value: the
success return and the true return are the same number, so no caller can tell
them apart.

## The stub's own premise has expired

`lib/crtl/src/signal.c:4` says *"there is no rt_sigaction PAL bridge yet, so
handlers never fire"*. True when written. Since then `lib/rtl/signals.pas`
carries rt_sigaction with a restorer, `sigaltstack`/`SA_ONSTACK`, and
siginfo/ucontext — `feature-signal-handlers` and
`feature-signal-siginfo-ucontext` are both in `done/`, with
`test/test_signal_altstack.pas` and `test/test_pal_signal.pas` passing. The
machinery is one lane over.

**So this is a REACH, not a build.** Two halves: a PAL entry that exposes what
signals.pas already does (Track A), and crtl's `sigaction`/`signal`/`raise`
lowering onto it (Track B, this ticket's lane). Filed in B because the stub is
B's file; whoever takes it should expect to need one A-side entry and should
say so rather than re-implementing rt_sigaction inside crtl — a second
restorer, a second dispatch and a second altstack policy is exactly the "two
mechanisms for one concept" that `root-cause-over-microfix.md` warns about.

## What it bounds

Every signal-using C program. In busybox specifically: `init` (SIGHUP/SIGUSR1/
SIGTERM), `hush` (job control, SIGCHLD, SIGINT), `syslogd`, `crond`, `top`,
`watchdog`. They compile, link and start.

**The 853-case busybox corpus cannot see this**, for the same structural reason
it could not see the offsetof truncation: 516 of the 621 cases in the 258-applet
run — and the equivalent majority at 374 — are `applet --help`, which prints a
string literal and installs nothing. See
[[feature-c-corpus-busybox-394-applets]] and frankD's real-argument case group
(`d0104ec8e`), which is the instrument that could.

## Repro

    #include <signal.h>
    #include <unistd.h>
    static void h(int s){ (void)s; _exit(0); }
    int main(void){ struct sigaction sa; memset(&sa,0,sizeof sa); sa.sa_handler=h;
                    sigaction(SIGALRM,&sa,0); alarm(1); pause(); return 1; }

glibc exits 0. pxx prints `Alarm clock` and dies on SIGALRM.

## Found by

Writing row 10 of `test/c_crtl_busybox_394_gaps.c`
([[feature-b-crtl-function-gaps-at-394-busybox-applets]]). The row now tests
that `pause()` BLOCKS — fork, check the child is alive, kill it — because a
handler-based test cannot pass until this is fixed. **That is a workaround in a
test, and it is recorded here so the test can be strengthened when this lands**
rather than staying at the weaker assertion because nobody remembers why it is
weak.

## FIXED — 2026-09-04, franks-ab

### What it is now

    gcc/glibc oracle   pxx x86-64 / i386 / arm32 / aarch64
    9 rows             byte-identical, all four targets

`test/c_crtl_signal_dispositions.c`. The ticket's own repro — `sigaction(SIGALRM)`,
`alarm(1)`, `pause()` — exits 0 under both, where pxx used to print
`Alarm clock` and die.

### The reach, and why nothing was re-implemented

crtl calls one bridge, `__pxx_c_signal(sig, handler)` in `lib/rtl/pxxcio.pas`.
It parks the C function pointer in a 64-slot table and installs ONE
parameterless trampoline via `SetSignalHandler`; the trampoline reads
`__pxxSigNum` and calls the C handler with the number.

That is the same mechanism `lib/rtl/signals.pas` uses for the FPC `Signal()`
surface. **Two surfaces over one mechanism, not two mechanisms** — no second
restorer, no second altstack policy, no rt_sigaction inside crtl, which is what
this ticket asked for and what `root-cause-over-microfix.md` is about.

### What it refuses, and what it accepts without honouring

- **SA_SIGINFO → EINVAL.** The hook ABI passes ONE argument. Accepting it would
  call a three-argument handler with two garbage arguments, in signal context —
  the worst place to put a plausible wrong value. Portable code falls back to
  `sa_handler`, which is what it already does.
- **sa_mask → accepted, not installed.** No signals are blocked for the duration
  of a handler. A real divergence, recorded in the header, the source and here.
  Refusing would reject the majority of real callers (busybox fills `sa_mask`
  routinely) over a property few of them depend on.
- **No signal runtime → -1/ENOSYS, never 0.** ESP platforms, windowed xtensa,
  **wasm32** and `--no-signals` take the bridge's guarded else-arm. (wasm32 was
  not on that list when this was written and joined it the next day, `2466279ad`
  — see the postscript at the end.) Measured: `sigaction rc=-1
  errno=38`. Returning 0 was the whole defect; the fix must not reintroduce it
  on the targets it cannot serve.

### The test asserts EFFECTS, because rc cannot see this bug

Every row watches a counter the handler wrote, or the process surviving a
signal whose default disposition is fatal. **`rc=0` is exactly what the broken
version produced**, so a row checking the return code is a row that passes
against the bug. Row 5 watches a CHILD die, because the observable for "SIG_DFL
reverted" is death and a parent cannot report a disposition that kills it; it
reads `WIFSIGNALED`, not an exit code, since a shell's 128+n is a shell
convention rather than the wait status.

**The positive control needs no revert**, which is the best kind: built
`--no-signals`, the bridge refuses, the process is killed by its own `raise` at
row 1, and all nine rows move.

### Row 10 strengthened, as this ticket asked

`c_crtl_busybox_394_gaps.c` row 10 tested only that `pause()` BLOCKS, because a
handler could not fire. It now has four columns: blocks, never returned, a
SIGALRM handler wakes it, and it reports -1/EINTR. **The blocking half stays** —
the handler half cannot see it, since a `pause()` that returned immediately
would satisfy "handler ran and pause came back" just as well. Two properties,
two shapes.

### Two things that came out of the work

- **`PXX_HAS_SIGNALS`**, a compiler define (`lexer.inc`) reading the one
  predicate `TargetHasSignalRuntime`, with `--no-signals` folded in because a
  define has no diagnostic to emit. RTL code could not ask for this capability
  before: the only spellings were CPU and platform defines and **both are the
  wrong axis** — which is exactly how `signals.pas` spent four days refusing
  four targets that had gained the runtime.
- [[bug-b-crtl-waitpid-returns-enosys-on-riscv32-so-no-program-can-reap-a-child]]
  — found because row 5 forks. Eight of nine rows pass on riscv32; that one
  cannot, so the cross rows stop at three targets and the Makefile NAMES the
  slug rather than dropping the target quietly.

### One process note worth keeping

The first version of the `PXX_HAS_SIGNALS` change added a `forward` for
`TargetHasSignalRuntime` to `compiler.pas` while `frontend_forwards.inc` already
had one. **PXX prescans and accepted it; `make compiler/pascal26` converged;
`gate.sh quick`'s FPC seed canary caught it** — `Function is already declared
Public/Forward`. Exactly the class CLAUDE.md says only the canary can see, and
it only ran because `compiler/**` was still uncommitted. The fix was to MOVE the
declaration earlier, not to add a second one.

## POSTSCRIPT — this change surfaced a hole in the predicate it asks (frankA, `2466279ad`)

`TargetHasSignalRuntime` had **no wasm32 arm**: ESP, then xtensa's ABI, then
`Result := True`. A wasm module has no OS to deliver a signal, so that was
wrong — and **invisible, because `EmitSignalRuntimeForTarget`'s wasm32 arm is
deliberately empty.** No runtime was emitted either way, so the predicate and
the dispatcher agreed by ACCIDENT on every target that had ever asked.

`PXX_HAS_SIGNALS` became a third consumer asking the predicate DIRECTLY, so
`pxxcio.pas` took the LIVE arm of `__pxx_c_signal` on wasm32, emitted
IR_SET_SIGNAL, and the backend refused the body: **3 → 56 IR op 65 gaps in one
commit, 55 of them `__pxx_c_signal`.** The `{$else}` −38 arm here is right; it
simply was not reached there.

Worth stating as the general shape: **two mechanisms that agree because neither
is exercised are not agreeing.** Routing a capability question through one
predicate is what converts that silence into a diagnosable failure — the hole
was pre-existing and had no way to be seen until something asked.

Confirmed here at HEAD rather than taken on report: the four cross targets are
still byte-identical to the gcc oracle after the predicate fix, and a Pascal
program pulling `pxxcio` now builds for wasm32.

