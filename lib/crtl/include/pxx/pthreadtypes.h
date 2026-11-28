/* SPDX-License-Identifier: Zlib */
/*
 * The pthread_*_t types alone, no functions: what glibc's bits/pthreadtypes.h
 * is. <pthread.h> includes it, and so does <sys/types.h>, because POSIX puts
 * these types in <sys/types.h> and code relies on that (systemd's structs
 * hold a pthread_mutex_t having included only <sys/types.h>; 39 units).
 * Moved here unchanged from <pthread.h>, comments included; the layouts and
 * sizes are explained there. feature-crtl-pthread-types-in-sys-types-h
 */
#ifndef PXX_CRTL_PXX_PTHREADTYPES_H
#define PXX_CRTL_PXX_PTHREADTYPES_H 1

#if defined(__x86_64__)
#define __PXX_PT_MUTEX_PAD   long __pxx_pad[2];
#define __PXX_PT_COND_PAD    int __pxx_pad[8]; long long __pxx_align;
#define __PXX_PT_ATTR_PAD    long __pxx_pad[5];
#define __PXX_PT_RWLOCK_PAD  int __pxx_pad[7]; long long __pxx_align;
#elif defined(__i386__)
#define __PXX_PT_MUTEX_PAD   long __pxx_pad[2];
#define __PXX_PT_COND_PAD    int __pxx_pad[10];
#define __PXX_PT_ATTR_PAD    int __pxx_pad[6];
#define __PXX_PT_RWLOCK_PAD  int __pxx_pad[3];
#else
#define __PXX_PT_MUTEX_PAD
#define __PXX_PT_COND_PAD
#define __PXX_PT_ATTR_PAD
#define __PXX_PT_RWLOCK_PAD
#endif

typedef long pthread_t;

typedef struct { int __state; int __type; long __owner; int __count; __PXX_PT_MUTEX_PAD } pthread_mutex_t;

typedef struct { int __type; } pthread_mutexattr_t;

typedef struct { int __detach; int __flags; unsigned long __stacksize; __PXX_PT_ATTR_PAD } pthread_attr_t;

typedef volatile int pthread_spinlock_t;

typedef unsigned int pthread_key_t;

typedef int pthread_once_t;

typedef struct { int __seq; int __clock; __PXX_PT_COND_PAD } pthread_cond_t;

typedef struct { int __clock; } pthread_condattr_t;

typedef struct {
  int __lock;     /* futex mutex word guarding the fields below */
  int __seq;      /* condvar word: state changed */
  int __readers;  /* readers holding it */
  int __writer;   /* 1 while a writer holds it */
  int __wwait;    /* writers waiting */
  __PXX_PT_RWLOCK_PAD
} pthread_rwlock_t;

#if defined(__x86_64__)
typedef struct { long __kind; } pthread_rwlockattr_t;               /* glibc: 8, aligned 8 */
#else
typedef struct { int __kind; int __pxx_pad; } pthread_rwlockattr_t; /* 8, aligned 4 */
#endif

#endif
