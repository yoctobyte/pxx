/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: unnamed POSIX semaphores (see include/semaphore.h). Errors
 * follow POSIX: -1 with errno.
 */
#include <semaphore.h>
#include <errno.h>

#ifdef __PXX_THREADSAFE__

#include <pthread.h>

struct __pxx_sem {
  pthread_mutex_t lock;
  pthread_cond_t nonzero;
  unsigned int value;
};
typedef char __pxx_sem_fits[sizeof(struct __pxx_sem) <= sizeof(sem_t) ? 1 : -1];
#define S(sem) ((struct __pxx_sem *)(void *)(sem))

int sem_init(sem_t *sem, int pshared, unsigned int value)
{
  if (pshared) { errno = ENOSYS; return -1; }
  if (value > SEM_VALUE_MAX) { errno = EINVAL; return -1; }
  pthread_mutex_init(&S(sem)->lock, 0);
  pthread_cond_init(&S(sem)->nonzero, 0);
  S(sem)->value = value;
  return 0;
}

int sem_destroy(sem_t *sem)
{
  pthread_cond_destroy(&S(sem)->nonzero);
  pthread_mutex_destroy(&S(sem)->lock);
  return 0;
}

int sem_wait(sem_t *sem)
{
  pthread_mutex_lock(&S(sem)->lock);
  while (S(sem)->value == 0) pthread_cond_wait(&S(sem)->nonzero, &S(sem)->lock);
  S(sem)->value--;
  pthread_mutex_unlock(&S(sem)->lock);
  return 0;
}

int sem_trywait(sem_t *sem)
{
  int r = 0;
  pthread_mutex_lock(&S(sem)->lock);
  if (S(sem)->value == 0) r = -1;
  else S(sem)->value--;
  pthread_mutex_unlock(&S(sem)->lock);
  if (r) errno = EAGAIN;
  return r;
}

/* abstime is an absolute CLOCK_REALTIME deadline, as for pthread_cond_timedwait */
int sem_timedwait(sem_t *sem, const struct timespec *abstime)
{
  int e = 0;
  if (abstime->tv_nsec < 0 || abstime->tv_nsec >= 1000000000L) { errno = EINVAL; return -1; }
  pthread_mutex_lock(&S(sem)->lock);
  while (S(sem)->value == 0 && e == 0) e = pthread_cond_timedwait(&S(sem)->nonzero, &S(sem)->lock, abstime);
  if (S(sem)->value > 0) { S(sem)->value--; e = 0; }
  pthread_mutex_unlock(&S(sem)->lock);
  if (e) { errno = e; return -1; }
  return 0;
}

int sem_post(sem_t *sem)
{
  pthread_mutex_lock(&S(sem)->lock);
  if (S(sem)->value >= SEM_VALUE_MAX) {
    pthread_mutex_unlock(&S(sem)->lock);
    errno = EOVERFLOW;
    return -1;
  }
  S(sem)->value++;
  pthread_cond_signal(&S(sem)->nonzero);
  pthread_mutex_unlock(&S(sem)->lock);
  return 0;
}

int sem_getvalue(sem_t *sem, int *sval)
{
  pthread_mutex_lock(&S(sem)->lock);
  *sval = (int)S(sem)->value;
  pthread_mutex_unlock(&S(sem)->lock);
  return 0;
}

#else /* one thread: a plain count */

#define V(sem) (*(unsigned int *)(void *)(sem))

int sem_init(sem_t *sem, int pshared, unsigned int value)
{
  if (pshared) { errno = ENOSYS; return -1; }
  if (value > SEM_VALUE_MAX) { errno = EINVAL; return -1; }
  V(sem) = value;
  return 0;
}

int sem_destroy(sem_t *sem) { (void)sem; return 0; }

/* no other thread can post: a wait at zero would never return */
int sem_wait(sem_t *sem)
{
  if (V(sem) == 0) { errno = EDEADLK; return -1; }
  V(sem)--;
  return 0;
}

int sem_trywait(sem_t *sem)
{
  if (V(sem) == 0) { errno = EAGAIN; return -1; }
  V(sem)--;
  return 0;
}

/* nothing can post before the deadline either, but it is a deadline: report
   the timeout POSIX defines rather than waiting it out */
int sem_timedwait(sem_t *sem, const struct timespec *abstime)
{
  if (abstime->tv_nsec < 0 || abstime->tv_nsec >= 1000000000L) { errno = EINVAL; return -1; }
  if (V(sem) == 0) { errno = ETIMEDOUT; return -1; }
  V(sem)--;
  return 0;
}

int sem_post(sem_t *sem)
{
  if (V(sem) >= SEM_VALUE_MAX) { errno = EOVERFLOW; return -1; }
  V(sem)++;
  return 0;
}

int sem_getvalue(sem_t *sem, int *sval) { *sval = (int)V(sem); return 0; }

#endif

sem_t *sem_open(const char *name, int oflag, ...)
{
  (void)name; (void)oflag;
  errno = ENOSYS;
  return SEM_FAILED;
}

int sem_close(sem_t *sem) { (void)sem; errno = ENOSYS; return -1; }
int sem_unlink(const char *name) { (void)name; errno = ENOSYS; return -1; }
