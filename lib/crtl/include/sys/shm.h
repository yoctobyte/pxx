/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/shm.h> -- System V shared memory.
 *
 * shmat() RETURNS (void *) -1 ON FAILURE, NOT NULL, and that is the one thing
 * about this interface that catches everybody: `if (!p)' after a shmat is a
 * test that never fires, and the program then writes through -1. The kernel
 * cannot use NULL as the sentinel because a segment mapped at address 0 is
 * legal.
 *
 * THE TIME FIELDS SPLIT ON WORD SIZE. Where `long' is 64 bits shm_atime is one
 * field; where it is 32 the kernel sends a low word and a HIGH word, so the
 * struct has __shm_atime_high after it and the y2038 answer is the pair. A
 * 32-bit build with the 64-bit layout does not fail -- shmctl(IPC_STAT)
 * succeeds and every field from shm_dtime onwards is shifted.
 *
 * SHMLBA IS A CALL, NOT A CONSTANT, because it is the page size and crtl does
 * not bake one in: pxx targets machines with 4K and 16K pages from the same
 * headers. It matters only with SHM_RND, which rounds the requested attach
 * address down to a multiple of it.
 *
 * Found attempting busybox on i386: sysklogd/logread.c and syslogd.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_SHM_H
#define _CRTL_SYS_SHM_H

#include <sys/types.h>
#include <sys/ipc.h>
#include <unistd.h>   /* getpagesize, for SHMLBA */

typedef unsigned long shmatt_t;

#define SHMLBA (getpagesize())

/* Permission flags for shmget. */
#define SHM_R  0400   /* or S_IRUGO */
#define SHM_W  0200   /* or S_IWUGO */

/* Flags for shmat. */
#define SHM_RDONLY  010000    /* attach read-only, else read-write */
#define SHM_RND     020000    /* round attach address down to SHMLBA */
#define SHM_REMAP   040000    /* take over the region on attach */
#define SHM_EXEC    0100000   /* execution access */

/* Commands for shmctl, beyond the IPC_* ones. */
#define SHM_LOCK    11   /* lock segment (root only) */
#define SHM_UNLOCK  12   /* unlock segment (root only) */

/* ipcs(1) commands. */
#define SHM_STAT      13
#define SHM_INFO      14
#define SHM_STAT_ANY  15

#define SHM_HUGE_SHIFT  26
#define SHM_HUGE_MASK   0x3f

struct shmid_ds {
  struct ipc_perm shm_perm;   /* operation permission struct */
  size_t          shm_segsz;  /* size of segment in bytes */
#if __SIZEOF_LONG__ < 8
  time_t          shm_atime;  /* time of last shmat() */
  unsigned long   __shm_atime_high;
  time_t          shm_dtime;  /* time of last shmdt() */
  unsigned long   __shm_dtime_high;
  time_t          shm_ctime;  /* time of last change by shmctl() */
  unsigned long   __shm_ctime_high;
#else
  time_t          shm_atime;
  time_t          shm_dtime;
  time_t          shm_ctime;
#endif
  pid_t           shm_cpid;    /* pid of creator */
  pid_t           shm_lpid;    /* pid of last shmop */
  shmatt_t        shm_nattch;  /* number of current attaches */
  unsigned long   __glibc_reserved5;
  unsigned long   __glibc_reserved6;
};

struct shminfo {
  unsigned long shmmax;
  unsigned long shmmin;
  unsigned long shmmni;
  unsigned long shmseg;
  unsigned long shmall;
  unsigned long __glibc_reserved1;
  unsigned long __glibc_reserved2;
  unsigned long __glibc_reserved3;
  unsigned long __glibc_reserved4;
};

struct shm_info {
  int           used_ids;
  unsigned long shm_tot;    /* total allocated shm */
  unsigned long shm_rss;    /* total resident shm */
  unsigned long shm_swp;    /* total swapped shm */
  unsigned long swap_attempts;
  unsigned long swap_successes;
};

int    shmget(key_t key, size_t size, int shmflg);
void  *shmat(int shmid, const void *shmaddr, int shmflg);
int    shmdt(const void *shmaddr);
int    shmctl(int shmid, int cmd, struct shmid_ds *buf);

#endif
