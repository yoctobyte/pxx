/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: signal — sigset bit-ops are real; registration/masking calls
 * (signal, sigaction, sigprocmask, sigaltstack, raise) are LINK-ONLY stubs:
 * there is no rt_sigaction PAL bridge yet, so handlers never fire. tcc's
 * crash-backtrace setup compiles and runs inert through these.
 */

#include <signal.h>

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
