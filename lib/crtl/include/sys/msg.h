/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/msg.h> -- System V message queues.
 *
 * THE MESSAGE BUFFER IS NOT DECLARED HERE AND THAT IS THE INTERFACE. A caller
 * declares `struct { long mtype; char mtext[N]; }' itself, and msgsnd's `msgsz'
 * counts mtext ONLY -- not the long in front of it. Passing sizeof(the whole
 * struct) sends the padding as message bytes and is the classic way to get a
 * message four or eight bytes longer than intended, which msgrcv then delivers
 * intact to a reader that reads past its own buffer. glibc declares a
 * `struct msgbuf' with mtext[1] for documentation; it is not usable as-is and
 * is not repeated here.
 *
 * msgrcv's `msgtyp' IS SIGNED AND THE SIGN IS A MODE: zero takes the first
 * message, positive takes the first of exactly that type, and NEGATIVE takes
 * the lowest type that is <= its absolute value. A caller that stores a type
 * in an unsigned and passes it silently loses the third mode.
 *
 * Found attempting busybox on i386, alongside the shm/sem pair the syslog
 * applets use.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_MSG_H
#define _CRTL_SYS_MSG_H

#include <sys/types.h>
#include <sys/ipc.h>

typedef unsigned long msgqnum_t;
typedef unsigned long msglen_t;

/* msgrcv flags. */
#define MSG_NOERROR  010000   /* truncate rather than fail on a long message */
#define MSG_EXCEPT   020000   /* take the first message NOT of msgtyp */
#define MSG_COPY     040000   /* copy, do not remove (with IPC_NOWAIT) */

/* ipcs(1) commands. */
#define MSG_STAT      11
#define MSG_INFO      12
#define MSG_STAT_ANY  13

struct msqid_ds {
  struct ipc_perm msg_perm;   /* operation permission struct */
#if __SIZEOF_LONG__ < 8
  time_t        msg_stime;    /* time of last msgsnd */
  unsigned long __msg_stime_high;
  time_t        msg_rtime;    /* time of last msgrcv */
  unsigned long __msg_rtime_high;
  time_t        msg_ctime;    /* time of last change */
  unsigned long __msg_ctime_high;
#else
  time_t        msg_stime;
  time_t        msg_rtime;
  time_t        msg_ctime;
#endif
  unsigned long __msg_cbytes; /* current number of bytes on the queue */
  msgqnum_t     msg_qnum;     /* messages currently on the queue */
  msglen_t      msg_qbytes;   /* maximum bytes allowed on the queue */
  pid_t         msg_lspid;    /* pid of last msgsnd */
  pid_t         msg_lrpid;    /* pid of last msgrcv */
  unsigned long __glibc_reserved4;
  unsigned long __glibc_reserved5;
};

struct msginfo {
  int msgpool;
  int msgmap;
  int msgmax;
  int msgmnb;
  int msgmni;
  int msgssz;
  int msgtql;
  unsigned short msgseg;
};

int     msgget(key_t key, int msgflg);
int     msgctl(int msqid, int cmd, struct msqid_ds *buf);
int     msgsnd(int msqid, const void *msgp, size_t msgsz, int msgflg);
ssize_t msgrcv(int msqid, void *msgp, size_t msgsz, long msgtyp, int msgflg);

#endif
