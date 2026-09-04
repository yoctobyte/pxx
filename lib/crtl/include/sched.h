/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sched.h> -- scheduling, CPU affinity, and namespaces.
 *
 * THE NAMESPACE CALLS LIVE HERE AND NOT IN <unistd.h>, because that is where
 * glibc puts them: unshare(2) and setns(2) are declared by <sched.h> under
 * _GNU_SOURCE, and busybox's util-linux/unshare.c and nsenter.c include this
 * header for exactly that. Putting them where the manual page's SYNOPSIS says
 * would compile nothing.
 *
 * sched_getaffinity RETURNS 0, NOT A LENGTH. The raw syscall answers with the
 * number of bytes it wrote; glibc turns that into 0-or-(-1)-with-errno, and
 * every caller here is written against glibc. Returning the kernel's number
 * would make `if (sched_getaffinity(...) == 0)' -- which is what
 * coreutils/nproc.c writes -- take the failure branch on every success.
 *
 * cpu_set_t is glibc's 1024-bit set, and the CPU_* macros go with it even
 * though nothing in the corpus uses them yet: busybox passes a bare
 * `unsigned long *' cast to void*, so the layout is not what it depends on,
 * but a <sched.h> without CPU_SET is one the next program will trip over.
 *
 * Found attempting busybox on i386, where there is no host <sched.h> to fall
 * back on: 5 translation units stop here (taskset, nproc, less, nsenter,
 * unshare). feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SCHED_H
#define _CRTL_SCHED_H

#include <stddef.h>
#include <sys/types.h>

/* Scheduling policies. */
#define SCHED_OTHER     0
#define SCHED_FIFO      1
#define SCHED_RR        2
#define SCHED_BATCH     3
#define SCHED_IDLE      5
#define SCHED_DEADLINE  6

struct sched_param {
  int sched_priority;
};

/* clone(2) / unshare(2) / setns(2) flags. The low byte is the exit signal. */
#define CSIGNAL              0x000000ff
#define CLONE_VM             0x00000100
#define CLONE_FS             0x00000200
#define CLONE_FILES          0x00000400
#define CLONE_SIGHAND        0x00000800
#define CLONE_PTRACE         0x00002000
#define CLONE_VFORK          0x00004000
#define CLONE_PARENT         0x00008000
#define CLONE_THREAD         0x00010000
#define CLONE_NEWNS          0x00020000
#define CLONE_SYSVSEM        0x00040000
#define CLONE_SETTLS         0x00080000
#define CLONE_PARENT_SETTID  0x00100000
#define CLONE_CHILD_CLEARTID 0x00200000
#define CLONE_DETACHED       0x00400000
#define CLONE_UNTRACED       0x00800000
#define CLONE_CHILD_SETTID   0x01000000
#define CLONE_NEWCGROUP      0x02000000
#define CLONE_NEWUTS         0x04000000
#define CLONE_NEWIPC         0x08000000
#define CLONE_NEWUSER        0x10000000
#define CLONE_NEWPID         0x20000000
#define CLONE_NEWNET         0x40000000
#define CLONE_IO             0x80000000

/* The affinity set: glibc's shape, 1024 bits of unsigned long. */
typedef unsigned long __cpu_mask;
#define __CPU_SETSIZE  1024
#define __NCPUBITS     (8 * (int)sizeof(__cpu_mask))
#define CPU_SETSIZE    __CPU_SETSIZE

typedef struct {
  __cpu_mask __bits[__CPU_SETSIZE / (8 * (int)sizeof(__cpu_mask))];
} cpu_set_t;

#define __CPUELT(cpu) ((cpu) / __NCPUBITS)
#define __CPUMASK(cpu) ((__cpu_mask)1 << ((cpu) % __NCPUBITS))

#define CPU_ZERO(setp) CPU_ZERO_S(sizeof(cpu_set_t), setp)
#define CPU_SET(cpu, setp)   ((setp)->__bits[__CPUELT(cpu)] |= __CPUMASK(cpu))
#define CPU_CLR(cpu, setp)   ((setp)->__bits[__CPUELT(cpu)] &= ~__CPUMASK(cpu))
#define CPU_ISSET(cpu, setp) \
  (((setp)->__bits[__CPUELT(cpu)] & __CPUMASK(cpu)) != 0)

void CPU_ZERO_S(size_t setsize, cpu_set_t *setp);
int  CPU_COUNT_S(size_t setsize, const cpu_set_t *setp);
#define CPU_COUNT(setp) CPU_COUNT_S(sizeof(cpu_set_t), setp)

int sched_yield(void);
int sched_getaffinity(pid_t pid, size_t cpusetsize, cpu_set_t *mask);
int sched_setaffinity(pid_t pid, size_t cpusetsize, const cpu_set_t *mask);
int sched_get_priority_max(int policy);
int sched_get_priority_min(int policy);

/* The scheduling-policy trio busybox util-linux/chrt.c needs. chrt calls all
   three plus the two priority bounds above, in one run: getscheduler at :154,
   getparam at :175, setscheduler at :199.

   SCHED_RESET_ON_FORK IS RETURNED BY sched_getscheduler AS A BIT IN THE POLICY,
   not stripped -- chrt.c:164 says so in its own comment and masks it off
   itself. So this returns the kernel's answer unmodified; helpfully clearing
   that bit would make chrt report the wrong policy for a reset-on-fork task. */
int sched_getscheduler(pid_t pid);
int sched_setscheduler(pid_t pid, int policy, const struct sched_param *param);
int sched_getparam(pid_t pid, struct sched_param *param);

int unshare(int flags);
int setns(int fd, int nstype);

#endif
