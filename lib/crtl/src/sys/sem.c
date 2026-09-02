/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: System V semaphores -- semget, semop, semctl.
 *
 * i386 HAS NO semop SYSCALL AND THAT IS THE WHOLE REASON THIS FILE IS NOT
 * THREE ONE-LINERS. Linux 5.1 gave 32-bit x86 direct numbers for semget,
 * semctl, shmget, shmctl, shmat, shmdt and the msg* family -- but NOT for
 * semop or semtimedop, which are still only reachable through the ipc()
 * multiplexer. Verified against this box's asm/unistd_32.h, 2026-09-02:
 * semget 393, semctl 394, shmget 395 ... msgctl 402, and no semop at all.
 * So the #ifdef ladder below is not defensive style; the SYS_semop arm simply
 * does not exist on a real target we ship.
 *
 * IPC() IS A MULTIPLEXER WITH A FIXED SIX-ARGUMENT SHAPE:
 *   ipc(call, first, second, third, ptr, fifth)
 * and SEMOP is call 1, with first=semid, second=nsops, ptr=sops. `third' is
 * unused for SEMOP and is the timeout pointer for SEMTIMEDOP (call 4). Getting
 * the argument POSITIONS wrong does not fail at the boundary -- the kernel
 * reads a semid out of what was meant to be a count.
 *
 * NO IPC_64 IS OR'D INTO semctl's cmd: the direct syscall passes it to the
 * kernel's handler itself, and a caller that adds it hands over a cmd the
 * kernel does not recognise. See src/sys/shm.c.
 *
 * THE FOURTH ARGUMENT TO semctl IS READ ONLY FOR THE COMMANDS THAT TAKE ONE.
 * GETVAL and GETPID are called with three arguments, so reading a vararg that
 * was never pushed would be reading someone else's stack -- glibc switches on
 * cmd for exactly this reason and so does this.
 *
 * KNOWN WRONG TODAY, AND DELIBERATELY NOT WORKED AROUND: the `va_arg(ap,
 * unsigned long)' below reads the union semun SLOT, which is what glibc and
 * musl do and what the psABI says is there. pxx currently puts a POINTER to a
 * caller temp in that slot for any aggregate passed through `...', so SETVAL,
 * IPC_STAT, IPC_SET, GETALL and SETALL hand the kernel an address where a
 * value or a struct pointer belongs. Reading `va_arg(ap, union semun)' instead
 * would agree with today's pxx and disagree with every gcc caller, so the code
 * stays as written.
 * bug-a-c-a-struct-through-the-variadic-tail-is-passed-as-a-pointer
 */
#include <sys/sem.h>
#include <stdarg.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

/* ipc() multiplexer call numbers (linux/ipc.h). */
#define CRTL_IPCCALL_SEMOP       1
#define CRTL_IPCCALL_SEMGET      2
#define CRTL_IPCCALL_SEMCTL      3
#define CRTL_IPCCALL_SEMTIMEDOP  4

int semget(key_t key, int nsems, int semflg)
{
#ifdef SYS_semget
  return (int)syscall(SYS_semget, (long)key, (long)nsems, (long)semflg);
#elif defined(SYS_ipc)
  return (int)syscall(SYS_ipc, (long)CRTL_IPCCALL_SEMGET, (long)key,
                      (long)nsems, (long)semflg, (long)0, (long)0);
#else
  (void)key; (void)nsems; (void)semflg;
  errno = ENOSYS;
  return -1;
#endif
}

int semop(int semid, struct sembuf *sops, size_t nsops)
{
#ifdef SYS_semop
  return (int)syscall(SYS_semop, (long)semid, (long)sops, (long)nsops);
#elif defined(SYS_ipc)
  /* The i386 path. `third' is unused for SEMOP; sops goes in `ptr'. */
  return (int)syscall(SYS_ipc, (long)CRTL_IPCCALL_SEMOP, (long)semid,
                      (long)nsops, (long)0, (long)sops, (long)0);
#else
  (void)semid; (void)sops; (void)nsops;
  errno = ENOSYS;
  return -1;
#endif
}

int semctl(int semid, int semnum, int cmd, ...)
{
  unsigned long arg = 0;
  va_list ap;

  switch (cmd) {
  case SETVAL:
  case GETALL:
  case SETALL:
  case IPC_STAT:
  case IPC_SET:
  case IPC_INFO:
  case SEM_INFO:
  case SEM_STAT:
  case SEM_STAT_ANY:
    va_start(ap, cmd);
    arg = (unsigned long)va_arg(ap, unsigned long);
    va_end(ap);
    break;
  default:
    break;
  }

#ifdef SYS_semctl
  return (int)syscall(SYS_semctl, (long)semid, (long)semnum, (long)cmd,
                      (long)arg);
#elif defined(SYS_ipc)
  return (int)syscall(SYS_ipc, (long)CRTL_IPCCALL_SEMCTL, (long)semid,
                      (long)semnum, (long)cmd, (long)&arg, (long)0);
#else
  (void)semid; (void)semnum; (void)cmd; (void)arg;
  errno = ENOSYS;
  return -1;
#endif
}
