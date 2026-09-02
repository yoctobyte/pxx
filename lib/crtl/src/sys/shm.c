/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: System V shared memory -- shmget, shmat, shmdt, shmctl.
 *
 * NO IPC_64 IS OR'D INTO cmd, and that is not an omission. The DIRECT
 * shmctl(2) syscall passes IPC_64 to the kernel's own handler itself; only the
 * ipc() multiplexer parses a version out of the command. A caller that ORs it
 * in on top hands the kernel a cmd it does not recognise, and shmctl fails
 * with EINVAL on a perfectly good segment.
 *
 * shmat RETURNS (void *) -1 ON FAILURE, NOT NULL, because 0 is a legal
 * mapping address. syscall() has already turned the kernel's -errno into
 * -1/errno, so the -1 comes through as the pointer value and errno is set.
 *
 * #ifdef ON THE SYSCALL NUMBER, not on the architecture -- see src/sched.c.
 */
#include <sys/shm.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

int shmget(key_t key, size_t size, int shmflg)
{
#ifdef SYS_shmget
  return (int)syscall(SYS_shmget, (long)key, (long)size, (long)shmflg);
#else
  (void)key; (void)size; (void)shmflg;
  errno = ENOSYS;
  return -1;
#endif
}

void *shmat(int shmid, const void *shmaddr, int shmflg)
{
#ifdef SYS_shmat
  return (void *)(long)syscall(SYS_shmat, (long)shmid, (long)shmaddr,
                               (long)shmflg);
#else
  (void)shmid; (void)shmaddr; (void)shmflg;
  errno = ENOSYS;
  return (void *) -1;
#endif
}

int shmdt(const void *shmaddr)
{
#ifdef SYS_shmdt
  return (int)syscall(SYS_shmdt, (long)shmaddr);
#else
  (void)shmaddr;
  errno = ENOSYS;
  return -1;
#endif
}

int shmctl(int shmid, int cmd, struct shmid_ds *buf)
{
#ifdef SYS_shmctl
  return (int)syscall(SYS_shmctl, (long)shmid, (long)cmd, (long)buf);
#else
  (void)shmid; (void)cmd; (void)buf;
  errno = ENOSYS;
  return -1;
#endif
}
