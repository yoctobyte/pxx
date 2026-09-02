/* crtl: <sched.h> and <linux/fs.h>.
 *
 * Both found by attempting busybox for i386, where there is no host
 * /usr/include to fall back on: sched.h stopped 5 translation units (taskset,
 * nproc, less, nsenter, unshare) and linux/fs.h stopped 6 (blkdiscard,
 * blockdev, fsfreeze, fstrim, mkfs_ext2, partprobe).
 *
 * A WRONG IOCTL NUMBER DOES NOT FAIL TO COMPILE -- it issues a DIFFERENT
 * ioctl. BLKRRPART where BLKGETSIZE64 was meant rereads the partition table of
 * the disk whose size you asked for. So every number here is diffed against
 * the host's own kernel header, which is the only thing that can see a
 * transposition, and none of them is asserted from memory.
 *
 * Row 4 is the 32/64 split and it is DELIBERATE: BLKBSZGET, BLKBSZSET and
 * BLKGETSIZE64 are spelled with size_t in the kernel's own header, so their
 * encoded size -- and therefore the ioctl number -- differs between 32- and
 * 64-bit userspace (0x80041272 against 0x80081272). The kernel accepts both.
 * "Fixing" it to uint64_t would send 64-bit userspace a number nothing
 * answers, so the i386 row exists to pin the difference rather than to catch
 * it.
 *
 * sched_getaffinity RETURNS 0, not the kernel's byte count: row 8 is `rc' and
 * coreutils/nproc.c is written as `if (sched_getaffinity(...) == 0)'. Row 9
 * asks for a policy's priority range rather than a fixed number, because
 * SCHED_FIFO's range is the kernel's to choose.
 */
/* _GNU_SOURCE is for the ORACLE, not for us: glibc gates SCHED_BATCH,
   CLONE_NEW*, unshare and setns behind it, and crtl defines them
   unconditionally. Accepting what glibc asks a macro for is the allowed
   direction; without this line gcc cannot compile the comparison at all. */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <sched.h>
#include <linux/fs.h>
#include <stddef.h>

int main(void)
{
  cpu_set_t s;
  unsigned long mask[16];
  int rc;

  printf("1 %d %d %d %d %d %d\n", SCHED_OTHER, SCHED_FIFO, SCHED_RR,
         SCHED_BATCH, SCHED_IDLE, SCHED_DEADLINE);
  printf("2 %x %x %x %x %x %x %x\n", CLONE_NEWNS, CLONE_NEWCGROUP, CLONE_NEWUTS,
         CLONE_NEWIPC, CLONE_NEWUSER, CLONE_NEWPID, CLONE_NEWNET);
  printf("3 %x %x %d\n", CLONE_VM, CSIGNAL, CPU_SETSIZE);

  CPU_ZERO(&s); CPU_SET(0, &s); CPU_SET(65, &s); CPU_SET(129, &s);
  printf("4 %d %d %d %d %d\n", CPU_ISSET(0, &s) ? 1 : 0, CPU_ISSET(1, &s) ? 1 : 0,
         CPU_ISSET(65, &s) ? 1 : 0, CPU_ISSET(129, &s) ? 1 : 0, CPU_COUNT(&s));
  CPU_CLR(65, &s);
  printf("5 %d %d\n", CPU_ISSET(65, &s) ? 1 : 0, CPU_COUNT(&s));

  printf("6 %d\n", sched_yield());
  memset(mask, 0, sizeof mask);
  rc = sched_getaffinity(0, sizeof(mask), (void *)mask);
  printf("7 %d %d\n", rc, mask[0] != 0 ? 1 : 0);
  printf("8 %d\n", sched_get_priority_max(SCHED_FIFO) >
                   sched_get_priority_min(SCHED_FIFO) ? 1 : 0);
  printf("9 %d\n", unshare(0));

  printf("10 %lx %lx %lx %lx\n", (unsigned long)BLKROSET, (unsigned long)BLKROGET,
         (unsigned long)BLKRRPART, (unsigned long)BLKGETSIZE);
  printf("11 %lx %lx %lx %lx\n", (unsigned long)BLKFLSBUF, (unsigned long)BLKRASET,
         (unsigned long)BLKRAGET, (unsigned long)BLKFRASET);
  printf("12 %lx %lx %lx %lx\n", (unsigned long)BLKFRAGET, (unsigned long)BLKSECTSET,
         (unsigned long)BLKSECTGET, (unsigned long)BLKSSZGET);
  printf("13 %lx %lx %lx %lx\n", (unsigned long)BLKDISCARD, (unsigned long)BLKIOMIN,
         (unsigned long)BLKIOOPT, (unsigned long)BLKALIGNOFF);
  printf("14 %lx %lx %lx %lx\n", (unsigned long)BLKPBSZGET,
         (unsigned long)BLKDISCARDZEROES, (unsigned long)BLKSECDISCARD,
         (unsigned long)BLKROTATIONAL);
  printf("15 %lx %lx %lx\n", (unsigned long)BLKZEROOUT, (unsigned long)FIBMAP,
         (unsigned long)FIGETBSZ);
  printf("16 %lx %lx %lx\n", (unsigned long)FIFREEZE, (unsigned long)FITHAW,
         (unsigned long)FITRIM);
  printf("17 %d %d %d %d\n", (int)sizeof(struct fstrim_range),
         (int)offsetof(struct fstrim_range, start),
         (int)offsetof(struct fstrim_range, len),
         (int)offsetof(struct fstrim_range, minlen));
  /* the size_t-typed three, which is where 32- and 64-bit userspace differ */
  printf("18 %lx %lx %lx\n", (unsigned long)BLKBSZGET, (unsigned long)BLKBSZSET,
         (unsigned long)BLKGETSIZE64);
  return 0;
}
