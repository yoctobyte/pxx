/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: signal — sigset bit-ops are real; registration/masking calls
 * (signal, sigaction, sigprocmask, sigaltstack, raise) are LINK-ONLY stubs:
 * there is no rt_sigaction PAL bridge yet, so handlers never fire. tcc's
 * crash-backtrace setup compiles and runs inert through these.
 */

#include <signal.h>
#include <errno.h>

extern int __pxx_kill(int pid, int sig);

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

__sighandler_t signal(int sig, __sighandler_t func) {
  (void)sig;
  return func;
}

int raise(int sig) {
  (void)sig;
  return 0;
}

int sigprocmask(int how, const sigset_t *set, sigset_t *oldset) {
  (void)how; (void)set;
  if (oldset) sigemptyset(oldset);
  return 0;
}

int sigaction(int sig, const struct sigaction *act, struct sigaction *oact) {
  (void)sig; (void)act; (void)oact;
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

/* strsignal: the human name of a signal.
 *
 * The strings are glibc's VERBATIM, read off the host rather than invented,
 * because they are OUTPUT: a shell prints them for a killed child ("Segmentation
 * fault", "Killed") and any differential test against a gcc-built binary
 * compares them byte for byte. A plausible synonym would be a silent diff on
 * every job that dies.
 *
 * Declared in <string.h>, which is where POSIX puts it, not in <signal.h>.
 *
 * The returned pointer is to storage the caller must not modify and that a
 * later call may overwrite -- the same contract glibc has. Only the unknown
 * branch actually uses the buffer; the named signals return string literals. */
static char __strsignal_buf[32];

char *strsignal(int sig) {
  static const char *const names[] = {
    /*  0 */ 0,
    /*  1 */ "Hangup",
    /*  2 */ "Interrupt",
    /*  3 */ "Quit",
    /*  4 */ "Illegal instruction",
    /*  5 */ "Trace/breakpoint trap",
    /*  6 */ "Aborted",
    /*  7 */ "Bus error",
    /*  8 */ "Floating point exception",
    /*  9 */ "Killed",
    /* 10 */ "User defined signal 1",
    /* 11 */ "Segmentation fault",
    /* 12 */ "User defined signal 2",
    /* 13 */ "Broken pipe",
    /* 14 */ "Alarm clock",
    /* 15 */ "Terminated",
    /* 16 */ "Stack fault",
    /* 17 */ "Child exited",
    /* 18 */ "Continued",
    /* 19 */ "Stopped (signal)",
    /* 20 */ "Stopped",
    /* 21 */ "Stopped (tty input)",
    /* 22 */ "Stopped (tty output)",
    /* 23 */ "Urgent I/O condition",
    /* 24 */ "CPU time limit exceeded",
    /* 25 */ "File size limit exceeded",
    /* 26 */ "Virtual timer expired",
    /* 27 */ "Profiling timer expired",
    /* 28 */ "Window changed",
    /* 29 */ "I/O possible",
    /* 30 */ "Power failure",
    /* 31 */ "Bad system call"
  };
  if (sig > 0 && sig < (int)(sizeof(names) / sizeof(names[0])) && names[sig])
    return (char *)names[sig];
  /* glibc's exact wording for anything else, signal 0 included. */
  {
    char *p = __strsignal_buf;
    const char *pre = "Unknown signal ";
    int n = sig, neg = 0, i = 0;
    char digits[16];
    while (*pre) *p++ = *pre++;
    if (n < 0) { neg = 1; n = -n; }
    if (n == 0) digits[i++] = '0';
    while (n > 0) { digits[i++] = (char)('0' + n % 10); n /= 10; }
    if (neg) *p++ = '-';
    while (i > 0) *p++ = digits[--i];
    *p = '\0';
  }
  return __strsignal_buf;
}
