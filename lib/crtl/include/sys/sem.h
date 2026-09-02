/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/sem.h> -- System V semaphores.
 *
 * struct semid_ds HERE IS THE KERNEL'S semid64_ds AND IS THEREFORE *NOT*
 * BYTE-COMPATIBLE WITH GLIBC'S STRUCT OF THE SAME NAME. Measured 2026-09-02:
 * glibc's is 104 bytes on x86-64 and 64 on i386, the kernel's is 88 and 64.
 * glibc carries __sem_otime_high / __sem_ctime_high on BOTH widths and its
 * semctl() TRANSLATES field by field into a kernel-shaped struct on the way
 * through. crtl passes the caller's struct straight to the kernel, so the
 * caller's struct has to be the kernel's -- doing it glibc's way would mean a
 * copy in every semctl to buy compatibility with a layout no crtl program can
 * observe, since crtl programs compile against this header.
 *
 * THE DIVERGENCE IS INVISIBLE TO CORRECT CODE and the test proves it
 * behaviourally rather than structurally: create a set, IPC_STAT it, and check
 * sem_nsems is the number that was asked for. gcc gets there through glibc's
 * translation and pxx through the kernel layout, and both must print the same
 * number. A layout row comparing sizeof against glibc would FAIL here and
 * would be right to.
 *
 * union semun IS DELIBERATELY NOT DEFINED. POSIX says the caller declares it,
 * glibc stopped defining it decades ago and says so with
 * _SEM_SEMUN_UNDEFINED, and a header that defines it breaks every program
 * that declares its own.
 *
 * SEM_UNDO IS 0x1000 AND IPC_NOWAIT IS 04000 -- both go in sembuf.sem_flg and
 * they are the only two that do, so there is nothing to confuse them with; but
 * IPC_NOWAIT there means "fail rather than block", while the same bit in
 * semget's flags is part of the permission word. Same name, same struct
 * family, two meanings.
 *
 * Found attempting busybox on i386: sysklogd/logread.c and syslogd.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_SEM_H
#define _CRTL_SYS_SEM_H

#include <sys/types.h>
#include <sys/ipc.h>

/* Flags for sembuf.sem_flg. IPC_NOWAIT comes from <sys/ipc.h>. */
#define SEM_UNDO  0x1000   /* undo the operation on exit */

/* Commands for semctl. */
#define GETPID   11   /* get sempid */
#define GETVAL   12   /* get semval */
#define GETALL   13   /* get all semval's */
#define GETNCNT  14   /* get semncnt */
#define GETZCNT  15   /* get semzcnt */
#define SETVAL   16   /* set semval */
#define SETALL   17   /* set all semval's */

/* ipcs(1) commands. */
#define SEM_STAT      18
#define SEM_INFO      19
#define SEM_STAT_ANY  20

/* glibc's marker: the caller declares union semun, not the header. */
#define _SEM_SEMUN_UNDEFINED 1

/* The kernel's semid64_ds -- see the note above about glibc's differing. */
struct semid_ds {
  struct ipc_perm sem_perm;   /* operation permission struct */
#if __SIZEOF_LONG__ < 8
  time_t        sem_otime;    /* last semop() time */
  unsigned long __sem_otime_high;
  time_t        sem_ctime;    /* last change by semctl() */
  unsigned long __sem_ctime_high;
#else
  time_t        sem_otime;
  time_t        sem_ctime;
#endif
  unsigned long sem_nsems;    /* number of semaphores in the set */
  unsigned long __glibc_reserved3;
  unsigned long __glibc_reserved4;
};

struct sembuf {
  unsigned short sem_num;  /* semaphore index in the array */
  short          sem_op;   /* operation */
  short          sem_flg;  /* SEM_UNDO, IPC_NOWAIT */
};

struct seminfo {
  int semmap;
  int semmni;
  int semmns;
  int semmnu;
  int semmsl;
  int semopm;
  int semume;
  int semusz;
  int semvmx;
  int semaem;
};

int semget(key_t key, int nsems, int semflg);
int semop(int semid, struct sembuf *sops, size_t nsops);
int semctl(int semid, int semnum, int cmd, ...);

#endif
