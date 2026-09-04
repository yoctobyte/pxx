/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SIGNAL_H
#define PXX_CRTL_SIGNAL_H 1

#include <time.h>   /* struct timespec, for sigtimedwait */

typedef int sig_atomic_t;

#define SIG_DFL ((void (*)(int))0)
#define SIG_IGN ((void (*)(int))1)
#define SIG_ERR ((void (*)(int))-1)

/* The Linux asm-generic signal numbers, which is every target pxx has: x86-64,
   i386, aarch64, arm32, riscv and xtensa all use this set. (MIPS, SPARC and
   Alpha renumber from SIGUSR1 up -- none of them is a pxx target, and adding
   one means splitting this block per-arch rather than editing it in place.)
   Read off the host with a generated program rather than typed from memory. */
#define SIGHUP     1
#define SIGINT     2
#define SIGQUIT    3
#define SIGILL     4
#define SIGTRAP    5
#define SIGABRT    6
#define SIGIOT     6
#define SIGBUS     7
#define SIGFPE     8
#define SIGKILL    9
#define SIGUSR1    10
#define SIGSEGV    11
#define SIGUSR2    12
#define SIGPIPE    13
#define SIGALRM    14
#define SIGTERM    15
#define SIGSTKFLT  16
#define SIGCHLD    17
#define SIGCONT    18
#define SIGSTOP    19
#define SIGTSTP    20
#define SIGTTIN    21
#define SIGTTOU    22
#define SIGURG     23
#define SIGXCPU    24
#define SIGXFSZ    25
#define SIGVTALRM  26
#define SIGPROF    27
#define SIGWINCH   28
#define SIGIO      29
#define SIGPOLL    29
#define SIGPWR     30
#define SIGSYS     31
#define SIGUNUSED  31

/* NSIG is a COUNT, not a maximum: signals run 1..64 (32..64 are the realtime
   ones), so `for (i = 1; i < NSIG; i++)' covers them all and `char t[NSIG]'
   indexes safely by signal number. Getting it wrong is silent -- a shell sizes
   its trap table with it. */
#define _NSIG 65
#define NSIG _NSIG

#define SIG_BLOCK   0
#define SIG_UNBLOCK 1
#define SIG_SETMASK 2

#define SA_SIGINFO 0x00000004
#define SA_ONSTACK 0x08000000
#define SA_RESTART 0x10000000

/* si_code values for SIGFPE */
#define FPE_INTDIV 1
#define FPE_INTOVF 2
#define FPE_FLTDIV 3

typedef void (*__sighandler_t)(int);
__sighandler_t signal(int sig, __sighandler_t func);
/* The unprefixed spelling, which is what programs actually write. glibc
   publishes both; busybox's include/platform.h defines it for itself ONLY
   under !HAVE_SIGHANDLER_T, and HAVE_SIGHANDLER_T is its DEFAULT -- so a libc
   that publishes only the __-prefixed name gets neither, and shell/hush.c
   fails on a type it was told existed. */
typedef __sighandler_t sighandler_t;
int raise(int sig);
int kill(int pid, int sig);

/* POSIX signal surface — TYPES are Linux/glibc-shaped; sigaction/sigprocmask/
   sigaltstack are LINK-ONLY STUBS for now (no rt_sigaction PAL bridge yet), so
   handlers registered through them never fire. Enough for tcc's optional
   crash-backtrace setup to compile and run inert. */
typedef struct { unsigned long __val[16]; } sigset_t;

typedef struct {
  int si_signo;
  int si_errno;
  int si_code;
  int __pad0;
  void *si_addr;
  long __pad[24];
} siginfo_t;

typedef struct {
  void *ss_sp;
  int ss_flags;
  unsigned long ss_size;
} stack_t;

#define SS_ONSTACK 1
#define SS_DISABLE 2

struct sigaction {
  void (*sa_handler)(int);
  void (*sa_sigaction)(int, siginfo_t *, void *);
  sigset_t sa_mask;
  int sa_flags;
  void (*sa_restorer)(void);
};

int sigemptyset(sigset_t *set);
int sigfillset(sigset_t *set);
int sigaddset(sigset_t *set, int sig);

/* sigisemptyset(3) is a GNU extension, not POSIX -- busybox shell/hush.c uses
   it at :2126, :2666, :11907 and :11922 to decide whether a pending-signal set
   needs draining. Returns 1 for empty, 0 for non-empty, and NEVER -1: there is
   no error return, so `if (sigisemptyset(&s) < 0)' can never fire. */
int sigisemptyset(const sigset_t *set);
int sigdelset(sigset_t *set, int sig);
int sigismember(const sigset_t *set, int sig);
/* sigprocmask IS REAL -- see the note in src/signal.c. (It used to say "works
   where sigaction cannot yet"; sigaction became real on 2026-09-04 and the
   clause went with it.) */
int sigprocmask(int how, const sigset_t *set, sigset_t *oldset);
/* Collect a pending signal from `set'. `info' is IGNORED (NULL is passed to
   the kernel), so a caller that needs siginfo gets its struct untouched rather
   than filled with something unverified. Returns the signal number, or -1 with
   EAGAIN on timeout; a NULL timeout blocks. */
int sigtimedwait(const sigset_t *set, siginfo_t *info,
                 const struct timespec *timeout);
/* sigwait(3): the same wait with no timeout, reporting through *sig and
   returning a POSITIVE errno -- a different convention in the same family. */
int sigwait(const sigset_t *set, int *sig);
/* sigaction(2) REALLY INSTALLS since 2026-09-04 -- it returned 0 and did
   nothing before, which is what made it a bug rather than a gap. Two things it
   does NOT honour, and it REFUSES the first rather than pretending:
     SA_SIGINFO -> EINVAL. The hook ABI passes one argument, so a three-argument
       handler would be called with two garbage ones -- in signal context, which
       is the worst place for a plausible wrong value.
     sa_mask    -> accepted and NOT installed. No signals are blocked for the
       duration of the handler. Refusing here would reject most real callers
       (busybox fills sa_mask routinely) over a property few depend on, so it is
       recorded rather than hidden. */
int sigaction(int sig, const struct sigaction *act, struct sigaction *oact);

/* sigsuspend still FAILS with ENOSYS, and the reason has changed: it is no
   longer "no handler can ever fire" (they can now) but that atomically swapping
   the mask for the duration of a wait has no bridge. Failing stays the answer
   -- a sigsuspend that set the mask non-atomically would lose a signal
   delivered in the window, which is exactly the bug sigsuspend exists to avoid,
   and a wrong answer is worse than a refusal. sigprocmask + sigtimedwait is the
   working pair for a caller that can restructure. */
int sigsuspend(const sigset_t *mask);
int sigaltstack(const stack_t *ss, stack_t *oss);

#endif
