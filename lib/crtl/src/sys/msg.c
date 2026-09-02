/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: System V message queues -- msgget, msgsnd, msgrcv, msgctl.
 *
 * msgsnd's msgsz COUNTS mtext ONLY, not the `long mtype' in front of it, and
 * this file cannot enforce that -- it is the caller's arithmetic. It is
 * recorded here because the failure is silent in both directions: too large
 * sends padding as message bytes, too small truncates, and neither errors.
 *
 * MSGRCV RETURNS A LENGTH, SO IT IS ssize_t AND NOT int: a queue can hold a
 * message longer than a 16-bit int and the kernel returns the byte count it
 * copied. syscall() has turned -errno into -1/errno already, and -1 is
 * distinguishable from a length because a length is never negative.
 *
 * #ifdef ON THE SYSCALL NUMBER, not on the architecture -- see src/sched.c --
 * with the ipc() multiplexer behind it for targets that have no direct msg*
 * numbers. NO IPC_64 in cmd; see src/sys/shm.c.
 */
#include <sys/msg.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

#define CRTL_IPCCALL_MSGSND  11
#define CRTL_IPCCALL_MSGRCV  12
#define CRTL_IPCCALL_MSGGET  13
#define CRTL_IPCCALL_MSGCTL  14

/* MSGRCV's ipc() form takes the buffer AND the type through one pointer,
   because the multiplexer ran out of argument slots. This is the shape the
   kernel unpacks. */
struct crtl_ipc_kludge {
  void *msgp;
  long  msgtyp;
};

int msgget(key_t key, int msgflg)
{
#ifdef SYS_msgget
  return (int)syscall(SYS_msgget, (long)key, (long)msgflg);
#elif defined(SYS_ipc)
  return (int)syscall(SYS_ipc, (long)CRTL_IPCCALL_MSGGET, (long)key,
                      (long)msgflg, (long)0, (long)0, (long)0);
#else
  (void)key; (void)msgflg;
  errno = ENOSYS;
  return -1;
#endif
}

int msgctl(int msqid, int cmd, struct msqid_ds *buf)
{
#ifdef SYS_msgctl
  return (int)syscall(SYS_msgctl, (long)msqid, (long)cmd, (long)buf);
#elif defined(SYS_ipc)
  return (int)syscall(SYS_ipc, (long)CRTL_IPCCALL_MSGCTL, (long)msqid,
                      (long)cmd, (long)0, (long)buf, (long)0);
#else
  (void)msqid; (void)cmd; (void)buf;
  errno = ENOSYS;
  return -1;
#endif
}

int msgsnd(int msqid, const void *msgp, size_t msgsz, int msgflg)
{
#ifdef SYS_msgsnd
  return (int)syscall(SYS_msgsnd, (long)msqid, (long)msgp, (long)msgsz,
                      (long)msgflg);
#elif defined(SYS_ipc)
  return (int)syscall(SYS_ipc, (long)CRTL_IPCCALL_MSGSND, (long)msqid,
                      (long)msgsz, (long)msgflg, (long)msgp, (long)0);
#else
  (void)msqid; (void)msgp; (void)msgsz; (void)msgflg;
  errno = ENOSYS;
  return -1;
#endif
}

ssize_t msgrcv(int msqid, void *msgp, size_t msgsz, long msgtyp, int msgflg)
{
#ifdef SYS_msgrcv
  return (ssize_t)syscall(SYS_msgrcv, (long)msqid, (long)msgp, (long)msgsz,
                          (long)msgtyp, (long)msgflg);
#elif defined(SYS_ipc)
  {
    struct crtl_ipc_kludge k;
    k.msgp = msgp;
    k.msgtyp = msgtyp;
    return (ssize_t)syscall(SYS_ipc, (long)CRTL_IPCCALL_MSGRCV, (long)msqid,
                            (long)msgsz, (long)msgflg, (long)&k, (long)0);
  }
#else
  (void)msqid; (void)msgp; (void)msgsz; (void)msgtyp; (void)msgflg;
  errno = ENOSYS;
  return -1;
#endif
}
