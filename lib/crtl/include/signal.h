/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SIGNAL_H
#define PXX_CRTL_SIGNAL_H 1

typedef int sig_atomic_t;

#define SIG_DFL ((void (*)(int))0)
#define SIG_IGN ((void (*)(int))1)
#define SIG_ERR ((void (*)(int))-1)

#define SIGABRT 6
#define SIGFPE 8
#define SIGILL 4
#define SIGINT 2
#define SIGSEGV 11
#define SIGTERM 15
#define SIGQUIT 3
#define SIGBUS 7
#define SIGKILL 9
#define SIGPIPE 13

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
int raise(int sig);

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
int sigdelset(sigset_t *set, int sig);
int sigismember(const sigset_t *set, int sig);
int sigprocmask(int how, const sigset_t *set, sigset_t *oldset);
int sigaction(int sig, const struct sigaction *act, struct sigaction *oact);
int sigaltstack(const stack_t *ss, stack_t *oss);

#endif
