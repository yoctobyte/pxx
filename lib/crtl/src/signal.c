/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: signal — sigset bit-ops, sigprocmask/sigtimedwait, and, since
 * 2026-09-04, REAL handler registration: signal(), sigaction() and raise()
 * install through __pxx_c_signal (lib/rtl/pxxcio.pas) onto the compiler's own
 * signal runtime, so a handler actually fires.
 *
 * They used to be link-only stubs RETURNING 0, which is what made it a bug
 * rather than a gap: a caller that checked the documented error path found
 * none, ran on with the kernel's default disposition, and was killed by the
 * first signal it had written a handler for, far from the call that reported
 * success (bug-b-crtl-signal-and-sigaction-report-success-and-install-nothing).
 *
 * WHAT IS STILL NOT HONOURED IS REFUSED, NOT IGNORED: SA_SIGINFO (the pxx hook
 * ABI is one-argument, so a three-argument handler would be called with the
 * wrong arguments) and sa_mask (no per-handler mask is installed). sigaltstack
 * is still a stub. Each says so at its own definition.
 */

#include <signal.h>
#include <errno.h>
#include <stddef.h>   /* size_t */
#include <time.h>

extern int __pxx_kill(int pid, int sig);
extern int __pxx_sigprocmask(int how, void *set, void *oldset, int setSize);
extern int __pxx_sigtimedwait(void *set, int setSize, int sec, int nsec);
extern int __pxx_c_signal(int sig, void *handler);
extern int __pxx_getpid(void);

/* 65, not 64: the array is indexed BY SIGNAL NUMBER, so slot 64 must exist and
   slot 0 is deliberately unused. Sizing it 64 would put SIGRTMAX one past the
   end -- the off-by-one that a `sig <= 64' bound reads as correct. */
#define __PXX_NSIG 65

#define __SIGSET_NWORDS 16
#define __SIGSET_WORDBITS (8 * (int)sizeof(unsigned long))

int sigemptyset(sigset_t *set) {
  int i;
  for (i = 0; i < __SIGSET_NWORDS; i++) set->__val[i] = 0;
  return 0;
}

int sigfillset(sigset_t *set) {
  int i;
  for (i = 0; i < __SIGSET_NWORDS; i++) set->__val[i] = ~0UL;
  return 0;
}

int sigaddset(sigset_t *set, int sig) {
  if (sig < 1) return -1;
  set->__val[(sig - 1) / __SIGSET_WORDBITS] |= 1UL << ((sig - 1) % __SIGSET_WORDBITS);
  return 0;
}

int sigdelset(sigset_t *set, int sig) {
  if (sig < 1) return -1;
  set->__val[(sig - 1) / __SIGSET_WORDBITS] &= ~(1UL << ((sig - 1) % __SIGSET_WORDBITS));
  return 0;
}

int sigismember(const sigset_t *set, int sig) {
  if (sig < 1) return -1;
  return (set->__val[(sig - 1) / __SIGSET_WORDBITS] >> ((sig - 1) % __SIGSET_WORDBITS)) & 1;
}

/* The C-side table exists for ONE reason: signal() and sigaction() must report
   the PREVIOUS disposition, and the bridge does not carry one back. Keeping it
   here rather than widening the bridge keeps the Pascal side to "install this"
   and leaves the C contract in the C file. */
static __sighandler_t __pxx_prev[__PXX_NSIG];

__sighandler_t signal(int sig, __sighandler_t func) {
  __sighandler_t prev;
  int rc;
  if (sig < 1 || sig >= __PXX_NSIG) { errno = EINVAL; return SIG_ERR; }
  prev = __pxx_prev[sig];
  rc = __pxx_c_signal(sig, (void *)func);
  if (rc < 0) { errno = -rc; return SIG_ERR; }
  __pxx_prev[sig] = func;
  return prev;
}

/* raise(3) is kill(getpid(), sig) and nothing more -- but it used to `return 0'
   without sending anything, so a program that raised a signal it had handled
   saw its handler not run and its own return value say fine. */
int raise(int sig) {
  return kill(__pxx_getpid(), sig);
}

/* THE KERNEL'S SIGSET IS EIGHT BYTES, NOT sizeof(sigset_t). _NSIG is 64 on
   every Linux architecture, so rt_sigprocmask takes a size of 8 and REJECTS
   anything else with EINVAL. crtl's sigset_t is deliberately wider (16 words,
   glibc-shaped) so that a program's `sigset_t' is layout-compatible with the
   one it might have been compiled against elsewhere; the low eight bytes hold
   signals 1..64 in exactly the kernel's bit order, on 32- and 64-bit alike,
   because both spell the bit as (sig-1) counted from __val[0]. So the pointer
   handed to the kernel is &set->__val[0] and the size is the constant below --
   passing sizeof(sigset_t) makes every call fail. */
#define PXX_KERNEL_SIGSETSIZE 8

/* sigprocmask IS REAL, unlike its neighbours above, and the difference is
   worth stating: BLOCKING a signal needs no handler and no return trampoline,
   which is the part this runtime cannot yet do. A blocked signal simply stays
   pending, and sigtimedwait below collects it -- that pair is how busybox's
   init waits for SIGCHLD without ever installing a handler, and it is why
   these two are implemented while sigaction is still a no-op. */
int sigprocmask(int how, const sigset_t *set, sigset_t *oldset) {
  int rc;
  if (oldset) sigemptyset(oldset);
  rc = __pxx_sigprocmask(how,
                         set ? (void *)&((sigset_t *)set)->__val[0] : 0,
                         oldset ? (void *)&oldset->__val[0] : 0,
                         PXX_KERNEL_SIGSETSIZE);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

/* sigtimedwait(2): wait for one of `set' to become pending, up to `timeout'.

   `info' IS IGNORED AND THAT IS DECLARED, not hidden: this passes NULL to the
   kernel, so a caller asking for siginfo gets its struct untouched rather than
   filled with a stale or invented one. busybox's init calls it with NULL, and
   the alternative -- marshalling a 128-byte siginfo whose layout this runtime
   has not verified against the kernel's -- is exactly the plausible-wrong-value
   shape this codebase spends its time on. When a caller needs it, the check is
   a field-by-field diff against a gcc build, not a guess.

   A NULL timeout blocks forever, which the PAL spells as a negative seconds
   rather than a second pointer argument. Returns the signal number, or -1 with
   EAGAIN on timeout. */
int sigtimedwait(const sigset_t *set, siginfo_t *info,
                 const struct timespec *timeout) {
  int rc;
  if (!set) { errno = EINVAL; return -1; }
  (void)info;
  if (timeout)
    rc = __pxx_sigtimedwait((void *)&((sigset_t *)set)->__val[0],
                            PXX_KERNEL_SIGSETSIZE,
                            (int)timeout->tv_sec, (int)timeout->tv_nsec);
  else
    rc = __pxx_sigtimedwait((void *)&((sigset_t *)set)->__val[0],
                            PXX_KERNEL_SIGSETSIZE, -1, 0);
  if (rc < 0) { errno = -rc; return -1; }
  return rc;
}

/* sigwait(3) is sigtimedwait with no timeout, and it reports through *sig with
   a POSITIVE errno return rather than -1/errno -- a different convention in
   the same family, which is why it is spelled out rather than aliased. */
int sigwait(const sigset_t *set, int *sig) {
  int rc = sigtimedwait(set, 0, 0);
  if (rc < 0) return errno;
  if (sig) *sig = rc;
  return 0;
}

/* sigaction(2). REFUSES what it cannot honour instead of accepting it:

   SA_SIGINFO asks for a three-argument handler and the pxx hook ABI passes one
   argument, so accepting it would call the caller's function with two garbage
   arguments -- a plausible wrong value in signal context, which is the worst
   place to put one. EINVAL is the honest answer and the caller can fall back to
   sa_handler, which is what portable code already does.

   sa_mask is NOT installed: no signals are blocked for the duration of the
   handler. That is a real divergence from POSIX and it is recorded rather than
   hidden -- a non-empty sa_mask does not refuse, because refusing would reject
   the majority of real callers (busybox fills sa_mask routinely) over a
   property most of them do not depend on. sa_flags bits other than SA_SIGINFO
   (SA_RESTART, SA_NOCLDSTOP, ...) are likewise accepted and not acted on; the
   underlying install is SA_RESTART-shaped already. */
int sigaction(int sig, const struct sigaction *act, struct sigaction *oact) {
  __sighandler_t prev;
  int rc;
  if (sig < 1 || sig >= __PXX_NSIG) { errno = EINVAL; return -1; }
  prev = __pxx_prev[sig];
  if (oact) {
    oact->sa_handler = prev;
    oact->sa_sigaction = 0;
    sigemptyset(&oact->sa_mask);
    oact->sa_flags = 0;
    oact->sa_restorer = 0;
  }
  if (!act) return 0;                 /* query-only, and oact is already filled */
  if (act->sa_flags & SA_SIGINFO) { errno = EINVAL; return -1; }
  rc = __pxx_c_signal(sig, (void *)act->sa_handler);
  if (rc < 0) { errno = -rc; return -1; }
  __pxx_prev[sig] = act->sa_handler;
  return 0;
}

int sigaltstack(const stack_t *ss, stack_t *oss) {
  (void)ss; (void)oss;
  return 0;
}

/* sigsuspend: with no rt_sigaction bridge no handler can ever fire, so a
   faithful sigsuspend would block FOREVER. It fails with ENOSYS instead —
   the one answer that is neither a lie nor a hang.

   Note the difference from its neighbours above: sigaction and sigprocmask
   return 0 because "registered, and it never fires" is harmless to a caller
   that only wanted to install a handler. Waiting on a signal that cannot
   arrive is not harmless, so this one reports the failure. */
int sigsuspend(const sigset_t *mask) {
  (void)mask;
  errno = ENOSYS;
  return -1;
}

/* kill: send a signal. Returns 0 or -1 with errno, like the C contract. */
int kill(int pid, int sig) {
  int r = __pxx_kill(pid, sig);
  if (r < 0) { errno = -r; return -1; }
  return 0;
}

/* strsignal() lived here and now lives in string.c, beside the header that
 * declares it. tools/crtl_reachability.py is what moved it: a program that
 * includes only <string.h> auto-pulls crtl/src/string.c, never this file, so
 * the declaration was reachable and the definition was not -- and the failure
 * is silent, because the link then resolves strsignal from the SYSTEM libc.
 * It needs nothing from this file: the table is indexed by signal NUMBER and
 * names no SIG* constant, which is why the move costs no include. */

/* sigisemptyset(3), GNU. 1 for empty, 0 for not, never -1 -- there is no error
 * return at all, so a caller cannot distinguish "empty" from "failed" and must
 * not try. busybox shell/hush.c relies on that at four sites.
 *
 * It walks the WHOLE __val array rather than the first word. sigset_t here is
 * sixteen unsigned longs and Linux uses only the first one or two, so reading
 * one word gives the right answer today on every target and would keep giving
 * it after a signal above 64 was ever set -- a test that passes for the wrong
 * reason. The loop costs nothing and cannot go stale.
 */
int sigisemptyset(const sigset_t *set)
{
  size_t i;
  if (!set) { errno = EINVAL; return 0; }
  for (i = 0; i < sizeof(set->__val) / sizeof(set->__val[0]); i++)
    if (set->__val[i] != 0UL) return 0;
  return 1;
}
