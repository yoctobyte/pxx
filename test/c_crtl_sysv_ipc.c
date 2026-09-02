/* crtl: the System V IPC family -- <sys/ipc.h>, <sys/shm.h>, <sys/sem.h>,
 * <sys/msg.h>. The last non-implementation blocker under busybox's
 * sysklogd/{syslogd,logread}.c, which is a shared-memory ring buffer guarded
 * by a semaphore set.
 *
 * THE ROWS ARE MOSTLY BEHAVIOURAL, because the thing that actually breaks here
 * is not a sizeof: i386 HAS NO semop OR semtimedop SYSCALL. Both go through the
 * ipc() multiplexer, whose six arguments are in a fixed order that nothing
 * checks -- get `nsops' and the sops pointer the wrong way round and the kernel
 * reads a semid out of a count, which fails with a plausible errno rather than
 * a crash. Rows 8-12 are that assertion.
 *
 * ROW 21 IS THE LAYOUT ROW AND IT IS LAST BECAUSE ONE OF ITS FIELDS IS
 * DELIBERATELY NOT GLIBC'S. ipc_perm (48/36), shmid_ds (112/84) and msqid_ds
 * (120/88) are byte-identical to glibc on both widths. `struct semid_ds' is
 * the KERNEL's semid64_ds -- 88 on x86-64 where glibc's is 104, and 64 on i386
 * where they agree -- because crtl hands the caller's struct straight to the
 * kernel while glibc translates field by field in its own semctl. The row
 * therefore records the number rather than diffing it, and sys/sem.h carries
 * the argument.
 *
 * ROW 5 IS WHY pid_t IS `int' AND NOT `long'. crtl had `typedef long pid_t',
 * which is invisible in every prototype (it is passed and returned in a
 * register either way) and wrong in exactly one place: a STRUCT. It put
 * shm_nattch at offset 88 where glibc has it at 84, so shmctl(IPC_STAT)
 * returned a segment size read out of the wrong field. Comparing shm_cpid to
 * getpid() is the row that pins it.
 *
 * NOT COVERED, DELIBERATELY: every semctl command that takes the fourth
 * `union semun' argument -- SETVAL, GETALL, SETALL, IPC_STAT, IPC_SET. pxx
 * passes an aggregate through `...' as a POINTER to a caller temp where the
 * psABI puts the aggregate's own bytes, so crtl's semctl (written the way
 * glibc and musl write it, reading the slot as an unsigned long) receives an
 * address. The implementation is correct against the ABI and is not being
 * worked around; the compiler bug is
 * bug-a-c-a-struct-through-the-variadic-tail-is-passed-as-a-pointer.
 * The commands busybox itself uses -- semop and semctl(IPC_RMID) -- are
 * unaffected and are what rows 7-13 cover.
 *
 * Every row diffed against gcc/glibc, natively and with `gcc -m32'.
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <sys/sem.h>
#include <sys/msg.h>

int main(void)
{
  int shmid, semid, msqid, rc;
  char *p;
  struct shmid_ds sds;
  struct msqid_ds mds;
  struct sembuf sb;
  struct { long mtype; char mtext[16]; } m;
  key_t k;

  /* ---- the flag constants are octal in <sys/ipc.h> and always have been ---- */
  printf("1 %d %d %d %d\n", IPC_CREAT, IPC_EXCL, IPC_NOWAIT, IPC_RMID);

  /* ---- shared memory: create, attach, write, detach, stat, remove ---- */
  shmid = shmget(IPC_PRIVATE, 4096, IPC_CREAT | 0600);
  printf("2 %d\n", shmid >= 0);
  p = (char *)shmat(shmid, 0, 0);
  printf("3 %d\n", p != (char *)-1);
  if (p != (char *)-1) {
    strcpy(p, "shm");
    /* Two statements, not one printf: `shmdt(p)` and `%s` on p in the same
       argument list is unspecified evaluation order, and gcc detaches first
       -- a genuine segfault in the ORACLE, which is the oracle earning its
       keep on the test rather than on the library. */
    printf("4 [%s]", p);
    printf(" %d\n", shmdt(p) == 0);
  } else {
    printf("4 [attach-failed] 0\n");
  }
  memset(&sds, 0, sizeof sds);
  rc = shmctl(shmid, IPC_STAT, &sds);
  printf("5 %d %d %d\n", rc, (int)sds.shm_segsz, sds.shm_cpid == getpid());
  printf("6 %d\n", shmctl(shmid, IPC_RMID, 0) == 0);

  /* ---- semaphores: create 3, raise one by 5, take 2 back, remove ----
     The value is set with semop rather than semctl(SETVAL) on purpose; see
     the NOT COVERED note above. A fresh set is all zeros, so +5 then -2
     leaves 3, and GETVAL takes no vararg. */
  semid = semget(IPC_PRIVATE, 3, IPC_CREAT | 0600);
  printf("7 %d\n", semid >= 0);
  sb.sem_num = 1; sb.sem_op = 5; sb.sem_flg = 0;
  printf("8 %d\n", semop(semid, &sb, 1) == 0);
  printf("9 %d\n", semctl(semid, 1, GETVAL));
  sb.sem_num = 1; sb.sem_op = -2; sb.sem_flg = 0;
  /* The call goes in a LOCAL first. Putting the semop and the GETVAL that
     reads its effect in one argument list is unspecified evaluation order,
     and gcc runs them right to left -- so the row printed the value BEFORE
     the operation and read 5 where 3 is correct. Same for `errno' below,
     which is an effect of the call sitting beside it. */
  rc = semop(semid, &sb, 1);
  printf("10 %d %d\n", rc == 0, semctl(semid, 1, GETVAL));
  printf("11 %d\n", semctl(semid, 1, GETPID) == getpid());
  /* A blocking op with IPC_NOWAIT must FAIL rather than hang: semaphore 0 is
     still 0, so -1 cannot be satisfied. */
  sb.sem_num = 0; sb.sem_op = -1; sb.sem_flg = IPC_NOWAIT;
  errno = 0;
  rc = semop(semid, &sb, 1);
  printf("12 %d %d\n", rc == -1, errno == EAGAIN);
  printf("13 %d\n", semctl(semid, 0, IPC_RMID) == 0);

  /* ---- message queue: send, stat, receive by type, remove ---- */
  msqid = msgget(IPC_PRIVATE, IPC_CREAT | 0600);
  printf("14 %d\n", msqid >= 0);
  m.mtype = 7;
  strcpy(m.mtext, "msg");
  rc = msgsnd(msqid, &m, 4, 0);
  printf("15 %d\n", rc == 0);
  memset(&mds, 0, sizeof mds);
  rc = msgctl(msqid, IPC_STAT, &mds);
  printf("16 %d %d %d\n", rc, (int)mds.msg_qnum, mds.msg_lspid == getpid());
  memset(&m, 0, sizeof m);
  rc = (int)msgrcv(msqid, &m, sizeof m.mtext, 7, 0);
  printf("17 %d %ld [%s]\n", rc, m.mtype, m.mtext);
  printf("18 %d\n", msgctl(msqid, IPC_RMID, 0) == 0);

  /* ---- ftok packs three fields; it does not hash ---- */
  k = ftok("/", 'x');
  printf("19 %d %d\n", k != (key_t)-1, (int)((k >> 24) & 0xff) == 'x');
  printf("20 %d\n", (int)ftok("/no/such/path/at/all", 'x'));

  /* The layouts. Three of the five must MATCH glibc and one must not; see the
     header comment. This is also what makes the i386 run a cross row with
     something to say -- four of these five numbers change with the width. */
  printf("21 %d %d %d %d %d\n",
         (int)sizeof(struct ipc_perm), (int)sizeof(struct shmid_ds),
         (int)sizeof(struct semid_ds), (int)sizeof(struct msqid_ds),
         (int)sizeof(struct sembuf));
  return 0;
}
