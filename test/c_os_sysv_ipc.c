/* System V IPC through the kernel translators (--os=freebsd, netbsd,
 * openbsd, dragonfly): every *_ds struct the program reads is the Linux one,
 * so each row checks a field the translator moved, and the semctl commands
 * Linux numbers differently from the BSDs (GETPID .. SETALL). A row prints
 * only what is the same on every system -- no ids, no times, only whether a
 * pid or time is the right one. Differential: the Linux build is the
 * reference.
 *
 * semtimedop is the one call FreeBSD, OpenBSD and DragonFly lack; the
 * translator polls semop there, and row 19 is its timeout.
 *
 * Three fields are the system's own answer and are checked loosely: FreeBSD
 * reports shm_segsz rounded up to a page (row 3), NetBSD never fills
 * msg_cbytes (row 24), and DragonFly leaves sem_otime at 0 (row 15). */
#define _GNU_SOURCE 1   /* glibc declares semtimedop only then */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <time.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <sys/sem.h>
#include <sys/msg.h>

union semun { int val; struct semid_ds *buf; unsigned short *array; };

int main(void)
{
  int shmid, semid, msqid, rc;
  char *p;
  struct shmid_ds sds;
  struct msqid_ds mds;
  struct semid_ds xds;
  struct sembuf sb[2];
  struct timespec ts;
  unsigned short vals[3];
  union semun u;
  struct { long mtype; char mtext[16]; } m;
  time_t t0 = time(0);

  /* ---- shared memory ---- */
  shmid = shmget(IPC_PRIVATE, 5000, IPC_CREAT | 0600);
  printf("1 %d\n", shmid >= 0);
  p = (char *)shmat(shmid, 0, 0);
  printf("2 %d\n", p != (char *)-1);
  strcpy(p, "hello");
  memset(&sds, 0, sizeof sds);
  rc = shmctl(shmid, IPC_STAT, &sds);
  printf("3 %d size>=5000:%d nattch=%lu cpid=%d lpid=%d mode=%o uid=%d atime=%d\n", rc,
         sds.shm_segsz >= 5000 && sds.shm_segsz <= 8192, (unsigned long)sds.shm_nattch,
         sds.shm_cpid == getpid(), sds.shm_lpid == getpid(),
         (unsigned)sds.shm_perm.mode & 0777, sds.shm_perm.uid == getuid(),
         sds.shm_atime >= t0);
  sds.shm_perm.mode = 0640;
  rc = shmctl(shmid, IPC_SET, &sds);
  memset(&sds, 0, sizeof sds);
  shmctl(shmid, IPC_STAT, &sds);
  printf("4 %d mode=%o size>=5000:%d\n", rc, (unsigned)sds.shm_perm.mode & 0777, sds.shm_segsz >= 5000);
  {
    char *q = (char *)shmat(shmid, 0, SHM_RDONLY);
    printf("5 %d [%s]\n", q != (char *)-1, q != (char *)-1 ? q : "");
    if (q != (char *)-1) shmdt(q);
  }
  printf("6 %d\n", shmdt(p));
  memset(&sds, 0, sizeof sds);
  shmctl(shmid, IPC_STAT, &sds);
  printf("7 nattch=%lu\n", (unsigned long)sds.shm_nattch);
  printf("8 %d\n", shmctl(shmid, IPC_RMID, 0));
  errno = 0;
  rc = shmctl(shmid, IPC_STAT, &sds);
  printf("9 %d %d\n", rc, errno == EINVAL || errno == EIDRM);

  /* ---- semaphores ---- */
  semid = semget(IPC_PRIVATE, 3, IPC_CREAT | 0600);
  printf("10 %d\n", semid >= 0);
  /* one call per statement where the order matters: printf's arguments
     are evaluated in an unspecified order (gcc goes right to left) */
  u.val = 5;
  rc = semctl(semid, 1, SETVAL, u);
  printf("11 %d %d\n", rc, semctl(semid, 1, GETVAL));
  vals[0] = 1; vals[1] = 2; vals[2] = 3;
  u.array = vals;
  printf("12 %d", semctl(semid, 0, SETALL, u));
  vals[0] = vals[1] = vals[2] = 0;
  u.array = vals;
  rc = semctl(semid, 0, GETALL, u);
  printf(" %d %u %u %u\n", rc, vals[0], vals[1], vals[2]);
  sb[0].sem_num = 2; sb[0].sem_op = -2; sb[0].sem_flg = 0;
  sb[1].sem_num = 0; sb[1].sem_op = 4; sb[1].sem_flg = SEM_UNDO;
  rc = semop(semid, sb, 2);
  printf("13 %d %d %d\n", rc, semctl(semid, 2, GETVAL), semctl(semid, 0, GETVAL));
  printf("14 pid=%d ncnt=%d zcnt=%d\n", semctl(semid, 2, GETPID) == getpid(),
         semctl(semid, 2, GETNCNT), semctl(semid, 2, GETZCNT));
  memset(&xds, 0, sizeof xds);
  u.buf = &xds;
  rc = semctl(semid, 0, IPC_STAT, u);
  printf("15 %d nsems=%lu mode=%o otime(0 on DragonFly)=%d\n", rc, (unsigned long)xds.sem_nsems,
         (unsigned)xds.sem_perm.mode & 0777, xds.sem_otime >= t0 || xds.sem_otime == 0);
  xds.sem_perm.mode = 0604;
  u.buf = &xds;
  rc = semctl(semid, 0, IPC_SET, u);
  memset(&xds, 0, sizeof xds);
  u.buf = &xds;
  semctl(semid, 0, IPC_STAT, u);
  printf("16 %d mode=%o nsems=%lu\n", rc, (unsigned)xds.sem_perm.mode & 0777, (unsigned long)xds.sem_nsems);
  sb[0].sem_num = 1; sb[0].sem_op = -9; sb[0].sem_flg = IPC_NOWAIT;
  errno = 0;
  rc = semop(semid, sb, 1);
  printf("17 %d %d\n", rc, errno == EAGAIN);
  sb[0].sem_num = 1; sb[0].sem_op = -1; sb[0].sem_flg = 0;
  ts.tv_sec = 0; ts.tv_nsec = 50000000;
  rc = semtimedop(semid, sb, 1, &ts);
  printf("18 %d %d\n", rc, semctl(semid, 1, GETVAL));
  sb[0].sem_op = -9;
  errno = 0;
  {
    time_t a = time(0);
    rc = semtimedop(semid, sb, 1, &ts);
    printf("19 %d %d %d\n", rc, errno == EAGAIN, time(0) - a <= 2);
  }
  printf("20 %d\n", semctl(semid, 0, IPC_RMID));
  errno = 0;
  rc = semctl(semid, 0, GETVAL);
  printf("21 %d %d\n", rc, errno == EINVAL || errno == EIDRM);

  /* ---- message queues ---- */
  msqid = msgget(IPC_PRIVATE, IPC_CREAT | 0600);
  printf("22 %d\n", msqid >= 0);
  m.mtype = 7; strcpy(m.mtext, "seven");
  rc = msgsnd(msqid, &m, 6, 0);
  m.mtype = 3; strcpy(m.mtext, "three");
  printf("23 %d %d\n", rc, msgsnd(msqid, &m, 6, IPC_NOWAIT));
  memset(&mds, 0, sizeof mds);
  rc = msgctl(msqid, IPC_STAT, &mds);
  printf("24 %d qnum=%lu cbytes(0 on NetBSD)=%lu lspid=%d stime=%d qbytes=%d mode=%o\n", rc,
         (unsigned long)mds.msg_qnum, (unsigned long)(mds.__msg_cbytes ? mds.__msg_cbytes : 12),
         mds.msg_lspid == getpid(), mds.msg_stime >= t0, mds.msg_qbytes > 0,
         (unsigned)mds.msg_perm.mode & 0777);
  memset(&m, 0, sizeof m);
  printf("25 %ld", (long)msgrcv(msqid, &m, sizeof m.mtext, 3, 0));
  printf(" %ld [%s]\n", m.mtype, m.mtext);
  memset(&m, 0, sizeof m);
  printf("26 %ld", (long)msgrcv(msqid, &m, sizeof m.mtext, 0, 0));
  printf(" %ld [%s]\n", m.mtype, m.mtext);
  errno = 0;
  rc = (int)msgrcv(msqid, &m, sizeof m.mtext, 0, IPC_NOWAIT);
  printf("27 %d %d\n", rc, errno == ENOMSG);
  m.mtype = 1; strcpy(m.mtext, "a long message");
  msgsnd(msqid, &m, 15, 0);
  errno = 0;
  rc = (int)msgrcv(msqid, &m, 4, 0, IPC_NOWAIT);
  printf("28 %d %d", rc, errno == E2BIG);
  rc = (int)msgrcv(msqid, &m, 4, 0, IPC_NOWAIT | MSG_NOERROR);
  printf(" %d [%.4s]\n", rc, m.mtext);
  memset(&mds, 0, sizeof mds);
  msgctl(msqid, IPC_STAT, &mds);
  mds.msg_perm.mode = 0620;
  mds.msg_qbytes = 1024;
  rc = msgctl(msqid, IPC_SET, &mds);
  memset(&mds, 0, sizeof mds);
  msgctl(msqid, IPC_STAT, &mds);
  printf("29 %d mode=%o qbytes=%lu qnum=%lu lrpid=%d\n", rc, (unsigned)mds.msg_perm.mode & 0777,
         (unsigned long)mds.msg_qbytes, (unsigned long)mds.msg_qnum, mds.msg_lrpid == getpid());
  printf("30 %d\n", msgctl(msqid, IPC_RMID, 0));
  errno = 0;
  rc = msgsnd(msqid, &m, 1, IPC_NOWAIT);
  printf("31 %d %d\n", rc, errno == EINVAL || errno == EIDRM);
  return 0;
}
