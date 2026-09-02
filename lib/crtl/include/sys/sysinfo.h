/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_SYSINFO_H
#define PXX_CRTL_SYS_SYSINFO_H 1

/* sysinfo(2).

   THE STRUCT IS THE KERNEL'S, FIELD FOR FIELD, and it has to be: the kernel
   writes into it, so a field in the wrong place is not an error -- it is
   `free' printing the buffer count as the total RAM. Transcribed from
   linux/sysinfo.h, whose __kernel_long_t / __kernel_ulong_t are `long' and
   `unsigned long' on every architecture pxx targets. The `_f' padding
   expression is upstream's own, kept verbatim rather than resolved to a
   number, so it stays right on 32- and 64-bit alike (20-2*8-4 = 0 bytes on
   64-bit, 20-2*4-4 = 8 on 32-bit).

   `procs' and `pad' are deliberately 16-bit and deliberately adjacent: two
   __u16 followed by longs is where a hand-written struct goes wrong.

   Found attempting busybox rung 2 -- init/init.c, procps/free.c, procps/ps.c
   and procps/uptime.c all include this header; without it they resolved to
   the HOST's /usr/include copy, which is the silent-ABI-mismatch path the
   compiler warns about. */

#define SI_LOAD_SHIFT 16

struct sysinfo {
  long uptime;                  /* seconds since boot */
  unsigned long loads[3];       /* 1, 5 and 15 minute load averages */
  unsigned long totalram;       /* total usable main memory size */
  unsigned long freeram;        /* available memory size */
  unsigned long sharedram;      /* amount of shared memory */
  unsigned long bufferram;      /* memory used by buffers */
  unsigned long totalswap;      /* total swap space size */
  unsigned long freeswap;       /* swap space still available */
  unsigned short procs;         /* number of current processes */
  unsigned short pad;           /* explicit padding for m68k */
  unsigned long totalhigh;      /* total high memory size */
  unsigned long freehigh;       /* available high memory size */
  unsigned int mem_unit;        /* memory unit size in bytes */
  char _f[20 - 2 * sizeof(unsigned long) - sizeof(unsigned int)];
};

/* Fills *info; 0 on success, -1/errno on failure. The load averages are fixed
   point, scaled by 1<<SI_LOAD_SHIFT, and the memory figures are in units of
   `mem_unit' bytes -- both are the kernel's conventions, not this runtime's. */
int sysinfo(struct sysinfo *info);

#endif
