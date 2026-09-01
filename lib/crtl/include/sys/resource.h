/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/resource.h> -- TYPES AND CONSTANTS ONLY.
 *
 * Deliberately declares NO functions. The PAL has no getrlimit/setrlimit/
 * getrusage entry (grep platform.pas: wait4 is the only one that even takes a
 * rusage pointer, and it passes it straight through), so a prototype here
 * would be a declaration crtl cannot satisfy -- and that is the precise shape
 * tools/crtl_reachability.py was written about: the call keeps its default
 * soname, the ELF writer emits a DT_NEEDED nobody asked for, and on a glibc
 * host the SYSTEM getrlimit answers it. A libc-free build would then be
 * running against glibc on x86-64 and failing to link on every cross target,
 * which is the worst of both. Without the declaration the call is a compile
 * error naming the function, which is the honest answer.
 *
 * UPDATE 2026-09-01: getrlimit/setrlimit ARE declared now, because the PAL work
 * the paragraph above names has been done -- PalPrlimit sits on prlimit64, one
 * syscall serving both.
 * UPDATE 2026-09-02: getpriority/setpriority likewise, on PalGetPriority/
 * PalSetPriority (busybox's `nice' and `renice'). The reasoning above still
 * stands for everything NOT listed here -- getrusage has no PAL entry, so it
 * stays undeclared and a call to it is a compile error naming the function,
 * which is the honest answer rather than a silent DT_NEEDED on glibc.
 *
 * prlimit64 rather than the legacy getrlimit/ugetrlimit pair: the legacy calls
 * use a 32-bit rlim_t on 32-bit targets and saturate at 4GB, so they would need
 * a per-word-size path AND would answer wrongly for a large limit. prlimit64 is
 * 64-bit on every target and exists on every kernel pxx builds for.
 *
 * The constants are the asm-generic set, which is what every target this
 * runtime builds for uses (x86-64, i386, aarch64, arm32, riscv32, xtensa).
 * Alpha, MIPS and SPARC renumber them and are not targets.
 */
#ifndef _CRTL_SYS_RESOURCE_H
#define _CRTL_SYS_RESOURCE_H

#include <sys/types.h>
#include <sys/time.h>

typedef unsigned long rlim_t;
typedef unsigned long long rlim64_t;

#define RLIM_INFINITY   ((rlim_t)~0UL)
#define RLIM_SAVED_MAX  RLIM_INFINITY
#define RLIM_SAVED_CUR  RLIM_INFINITY

#define RLIMIT_CPU        0
#define RLIMIT_FSIZE      1
#define RLIMIT_DATA       2
#define RLIMIT_STACK      3
#define RLIMIT_CORE       4
#define RLIMIT_RSS        5
#define RLIMIT_NPROC      6
#define RLIMIT_NOFILE     7
#define RLIMIT_MEMLOCK    8
#define RLIMIT_AS         9
#define RLIMIT_LOCKS     10
#define RLIMIT_SIGPENDING 11
#define RLIMIT_MSGQUEUE  12
#define RLIMIT_NICE      13
#define RLIMIT_RTPRIO    14
#define RLIMIT_RTTIME    15
#define RLIMIT_NLIMITS   16
#define RLIM_NLIMITS     RLIMIT_NLIMITS

#define RUSAGE_SELF      0
#define RUSAGE_CHILDREN  (-1)
#define RUSAGE_THREAD    1

#define PRIO_PROCESS 0
#define PRIO_PGRP    1
#define PRIO_USER    2

struct rlimit {
  rlim_t rlim_cur;
  rlim_t rlim_max;
};

struct rusage {
  struct timeval ru_utime;   /* user CPU time used */
  struct timeval ru_stime;   /* system CPU time used */
  long ru_maxrss;            /* maximum resident set size */
  long ru_ixrss;             /* integral shared memory size */
  long ru_idrss;             /* integral unshared data size */
  long ru_isrss;             /* integral unshared stack size */
  long ru_minflt;            /* page reclaims (soft page faults) */
  long ru_majflt;            /* page faults (hard page faults) */
  long ru_nswap;             /* swaps */
  long ru_inblock;           /* block input operations */
  long ru_oublock;           /* block output operations */
  long ru_msgsnd;            /* IPC messages sent */
  long ru_msgrcv;            /* IPC messages received */
  long ru_nsignals;          /* signals received */
  long ru_nvcsw;             /* voluntary context switches */
  long ru_nivcsw;            /* involuntary context switches */
};

/* Both operate on the CALLING process. Return 0, or -1 with errno.

   RLIM_INFINITY is (rlim_t)~0UL and is what the kernel actually stores for an
   unlimited resource, so it round-trips rather than being translated. */
int getrlimit(int resource, struct rlimit *rlim);
int setrlimit(int resource, const struct rlimit *rlim);

/* getpriority(2) returns the nice value, -20..19 -- and -1 IS A VALID ANSWER,
   so the return value alone cannot report failure. The POSIX contract is that
   the caller sets errno to 0 before the call and inspects it after; this
   implementation touches errno only on failure, which is what makes that
   contract work. busybox's coreutils/nice.c does exactly that. */
int getpriority(int which, id_t who);
int setpriority(int which, id_t who, int prio);

#endif
