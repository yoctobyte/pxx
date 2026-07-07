/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_UCONTEXT_H
#define PXX_CRTL_SYS_UCONTEXT_H 1

/* x86-64 Linux ucontext, glibc-compatible gregs layout — what the kernel
   lays out in a signal frame. Present so a <sys/ucontext.h> include resolves
   HERE instead of leaking the host's /usr/include chain into a libc-free
   build (tcc's crash-backtrace handler reads uc_mcontext.gregs[REG_RIP]).
   Signal DELIVERY is not implemented yet (sigaction is a stub); the layout is
   kernel-correct so a future rt_sigaction bridge needs no header change. */

#include <signal.h>

#define REG_R8      0
#define REG_R9      1
#define REG_R10     2
#define REG_R11     3
#define REG_R12     4
#define REG_R13     5
#define REG_R14     6
#define REG_R15     7
#define REG_RDI     8
#define REG_RSI     9
#define REG_RBP     10
#define REG_RBX     11
#define REG_RDX     12
#define REG_RAX     13
#define REG_RCX     14
#define REG_RSP     15
#define REG_RIP     16
#define REG_EFL     17
#define REG_CSGSFS  18
#define REG_ERR     19
#define REG_TRAPNO  20
#define REG_OLDMASK 21
#define REG_CR2     22

typedef long long gregset_t[23];

typedef struct {
  gregset_t gregs;
  void *fpregs;
  unsigned long long __reserved1[8];
} mcontext_t;

typedef struct ucontext_t {
  unsigned long uc_flags;
  struct ucontext_t *uc_link;
  stack_t uc_stack;
  mcontext_t uc_mcontext;
  sigset_t uc_sigmask;
} ucontext_t;

#endif
