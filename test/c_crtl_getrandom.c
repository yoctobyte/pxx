/* SPDX-License-Identifier: Zlib */
/* getrandom(2), asserted against glibc natively and against the native run on
   every cross target. NO EXPECTED VALUES -- the Makefile diffs the two builds.

   ROW 4 IS THE ROW A STUB CANNOT PASS. An implementation that returned bytes
   and ignored its flags passes rows 1, 2 and 3 completely: 32 bytes, two
   different buffers, not all zero. Only an UNDEFINED flag having to come back
   EINVAL says the flags reached the kernel at all -- and the flags are the
   entire reason this is a syscall here rather than a read of /dev/urandom.
   busybox's seedrng asks specifically for GRND_NONBLOCK and GRND_INSECURE and
   branches on which one answered.

   Row 3 is the other half of that pair and it is worth keeping even though it
   looks trivial: a wrapper that failed silently would leave the buffer as the
   memset left it, and rows 1 and 2 would still pass if the second buffer were
   filled and the first were not. `allzero 0' is the assertion that the bytes
   were actually written. */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/random.h>
#include <linux/random.h>
int main(void){
  unsigned char a[32], b[32]; ssize_t r1, r2; int zeros=0, i;
  memset(a,0,sizeof a); memset(b,0,sizeof b);
  r1 = getrandom(a, sizeof a, 0);
  r2 = getrandom(b, sizeof b, GRND_NONBLOCK);
  for (i=0;i<32;i++) if (a[i]==0) zeros++;
  printf("1 len %zd %zd\n", r1, r2);
  printf("2 differ %d\n", memcmp(a,b,sizeof a) != 0);
  printf("3 allzero %d\n", zeros==32);
  errno = 0;
  r1 = getrandom(a, sizeof a, 0x8000);          /* an undefined flag */
  printf("4 badflag %zd %d\n", r1, errno==EINVAL);
  printf("5 flags %d %d %d\n", GRND_NONBLOCK, GRND_RANDOM, GRND_INSECURE);
  return 0;
}
