---
slug: bug-b-crtl-signal-and-sigaction-report-success-and-install-nothing
title: "crtl's signal() and sigaction() return success and install no handler, while the runtime next door has working handlers"
track: B
prio: 70
type: bug
status: backlog
created: 2026-09-04
found-by: franks-ab
owner: ""
blocked-by: []
summary: "MEASURED on pinned v403. A C program calling sigaction() gets rc=0 and errno untouched, and the handler never runs: lib/crtl/src/signal.c:127 is `(void)sig; (void)act; (void)oact; return 0;`. signal() is the same. The failure is SILENT and the success is the problem -- a caller that checks the documented error path sees none, so the program runs with the kernel's DEFAULT disposition and dies on the first SIGALRM/SIGINT/SIGCHLD it was expecting to handle. Measured: sigaction(SIGALRM), alarm(1), pause() -> `Alarm clock`, process terminated, where glibc runs the handler. This is DOCUMENTED in that file's own header ('link-only stubs ... no rt_sigaction PAL bridge yet') but has no ticket, and the premise in that sentence has since expired: lib/rtl/signals.pas HAS rt_sigaction with a restorer, an altstack and siginfo/ucontext, all landed and tested (feature-signal-handlers, feature-signal-siginfo-ucontext, test_signal_altstack.pas). So the machinery exists one lane over and crtl does not reach it. Bounds every signal-using C program: busybox init, hush, syslogd, crond and the whole job-control path install handlers, and the 853-case corpus cannot see it because those cases only run `applet --help`."
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
