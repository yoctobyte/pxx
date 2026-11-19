/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/ptrace.h> -- ptrace(2), glibc's interface.
 *
 * Until this existed, `#include <sys/ptrace.h>` fell through to the HOST's
 * header, which drags in the host's <bits/types.h>; after crtl's
 * <sys/types.h> that failed on a conflicting __pid_t (crtl's was `long',
 * fixed to `int' in sys/_types.h at the same time). Rainyday's
 * drivers/lib/confine_test.c called ptrace through syscall() to get around it.
 *
 * The request numbers are the kernel's generic ones (include/uapi/linux/
 * ptrace.h), the same on every Linux architecture; the register requests
 * (GETREGS and friends) exist only where the kernel defines them, and a
 * request the kernel does not know answers EIO, as under glibc.
 *
 * ptrace IS VARIADIC, as in glibc: `long ptrace(enum __ptrace_request, ...)`,
 * reading pid, addr and data after the request. For the three PEEK requests
 * the kernel stores the word at *data, and the wrapper returns that word with
 * errno set to 0 -- so a caller tells a peeked -1 from a failure by errno,
 * exactly as with glibc.
 */
#ifndef _CRTL_SYS_PTRACE_H
#define _CRTL_SYS_PTRACE_H

#include <sys/types.h>

enum __ptrace_request {
  PTRACE_TRACEME = 0,
#define PTRACE_TRACEME PTRACE_TRACEME
  PTRACE_PEEKTEXT = 1,
#define PTRACE_PEEKTEXT PTRACE_PEEKTEXT
  PTRACE_PEEKDATA = 2,
#define PTRACE_PEEKDATA PTRACE_PEEKDATA
  PTRACE_PEEKUSER = 3,
#define PTRACE_PEEKUSER PTRACE_PEEKUSER
  PTRACE_POKETEXT = 4,
#define PTRACE_POKETEXT PTRACE_POKETEXT
  PTRACE_POKEDATA = 5,
#define PTRACE_POKEDATA PTRACE_POKEDATA
  PTRACE_POKEUSER = 6,
#define PTRACE_POKEUSER PTRACE_POKEUSER
  PTRACE_CONT = 7,
#define PTRACE_CONT PTRACE_CONT
  PTRACE_KILL = 8,
#define PTRACE_KILL PTRACE_KILL
  PTRACE_SINGLESTEP = 9,
#define PTRACE_SINGLESTEP PTRACE_SINGLESTEP
  PTRACE_GETREGS = 12,
#define PTRACE_GETREGS PTRACE_GETREGS
  PTRACE_SETREGS = 13,
#define PTRACE_SETREGS PTRACE_SETREGS
  PTRACE_GETFPREGS = 14,
#define PTRACE_GETFPREGS PTRACE_GETFPREGS
  PTRACE_SETFPREGS = 15,
#define PTRACE_SETFPREGS PTRACE_SETFPREGS
  PTRACE_ATTACH = 16,
#define PTRACE_ATTACH PTRACE_ATTACH
  PTRACE_DETACH = 17,
#define PTRACE_DETACH PTRACE_DETACH
  PTRACE_SYSCALL = 24,
#define PTRACE_SYSCALL PTRACE_SYSCALL
  PTRACE_SETOPTIONS = 0x4200,
#define PTRACE_SETOPTIONS PTRACE_SETOPTIONS
  PTRACE_GETEVENTMSG = 0x4201,
#define PTRACE_GETEVENTMSG PTRACE_GETEVENTMSG
  PTRACE_GETSIGINFO = 0x4202,
#define PTRACE_GETSIGINFO PTRACE_GETSIGINFO
  PTRACE_SETSIGINFO = 0x4203,
#define PTRACE_SETSIGINFO PTRACE_SETSIGINFO
  PTRACE_GETREGSET = 0x4204,
#define PTRACE_GETREGSET PTRACE_GETREGSET
  PTRACE_SETREGSET = 0x4205,
#define PTRACE_SETREGSET PTRACE_SETREGSET
  PTRACE_SEIZE = 0x4206,
#define PTRACE_SEIZE PTRACE_SEIZE
  PTRACE_INTERRUPT = 0x4207,
#define PTRACE_INTERRUPT PTRACE_INTERRUPT
  PTRACE_LISTEN = 0x4208
#define PTRACE_LISTEN PTRACE_LISTEN
};

/* PTRACE_SETOPTIONS bits */
#define PTRACE_O_TRACESYSGOOD   0x00000001
#define PTRACE_O_TRACEFORK      0x00000002
#define PTRACE_O_TRACEVFORK     0x00000004
#define PTRACE_O_TRACECLONE     0x00000008
#define PTRACE_O_TRACEEXEC      0x00000010
#define PTRACE_O_TRACEVFORKDONE 0x00000020
#define PTRACE_O_TRACEEXIT      0x00000040
#define PTRACE_O_TRACESECCOMP   0x00000080
#define PTRACE_O_EXITKILL       0x00100000
#define PTRACE_O_SUSPEND_SECCOMP 0x00200000

/* the event in a stop's status >> 16 */
#define PTRACE_EVENT_FORK       1
#define PTRACE_EVENT_VFORK      2
#define PTRACE_EVENT_CLONE      3
#define PTRACE_EVENT_EXEC       4
#define PTRACE_EVENT_VFORK_DONE 5
#define PTRACE_EVENT_EXIT       6
#define PTRACE_EVENT_SECCOMP    7
#define PTRACE_EVENT_STOP       128

long ptrace(enum __ptrace_request request, ...);

#endif
