/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: POSIX semaphores, <semaphore.h>.
 *
 * Unnamed semaphores (sem_init and friends). Under --threadsafe each is a count
 * under crtl's own pthread mutex and condition variable. Without it the
 * program has one thread, and a semaphore is a plain count; a wait at zero,
 * which could only block forever, fails with EDEADLK. Found building
 * micropython's unix port, whose thread layer waits on one for each thread it
 * suspends for garbage collection: crtl had no header, the host's supplied the
 * types, and the link failed on sem_init/sem_wait/sem_post.
 *
 * This header does NOT include <pthread.h>: programs include it without
 * starting a thread (tcc's tcc.h), and <pthread.h> without --threadsafe is a
 * compile error by design. sem_t is opaque storage; src/semaphore.c lays its
 * own struct over it and checks that it fits.
 *
 * pshared != 0 (shared between processes) and the named calls (sem_open,
 * sem_close, sem_unlink) fail with ENOSYS.
 */
#ifndef _PXX_SEMAPHORE_H
#define _PXX_SEMAPHORE_H

#include <time.h>

typedef union {
  char __size[128];
  long long __align;
} sem_t;

#define SEM_FAILED ((sem_t *)0)
#define SEM_VALUE_MAX 0x7fffffff

int sem_init(sem_t *sem, int pshared, unsigned int value);
int sem_destroy(sem_t *sem);
int sem_wait(sem_t *sem);
int sem_trywait(sem_t *sem);
int sem_timedwait(sem_t *sem, const struct timespec *abstime);
int sem_post(sem_t *sem);
int sem_getvalue(sem_t *sem, int *sval);

sem_t *sem_open(const char *name, int oflag, ...);
int sem_close(sem_t *sem);
int sem_unlink(const char *name);

#endif /* _PXX_SEMAPHORE_H */
