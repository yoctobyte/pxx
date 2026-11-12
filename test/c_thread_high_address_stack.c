/* A thread whose stack mmap returns an address with bit 31 set must start.

   arm32 widens a raw syscall return with an unconditional sign-extend, so a
   successful mmap at 0xa0000000+ arrives NEGATIVE. palthread tested the sign
   (`StackBase < 0`, `blk > 0`) and treated every such mapping as a failure:
   on a real 32-bit ARM kernel -- which places mappings near 0xa0000000 to
   0xbf000000 -- pthread_create returned EAGAIN every time (OpenWrt 25.12.6
   armv7, 2026-11-12). qemu-arm maps from low addresses upward, so the
   emulated test lane never saw it.

   This test makes qemu-arm behave like the real kernel: when a probe mapping
   comes out low, it reserves 1.25 GiB of address space it never touches
   (PROT_NONE, MAP_NORESERVE, so no memory is committed), which pushes the
   next mappings -- the thread stack and its TLS block -- above 0x80000000.
   A real 32-bit kernel needs no push (it maps top-down from ~0xb6000000, and
   a reservation there would push mappings DOWN). Positive control, measured:
   built before the palthread fix it prints "create rc=11" both under qemu-arm
   and on OpenWrt armv7; with the fix both print the line below. On x86-64
   and aarch64 nothing is reserved and the threads simply run. */
#include <stdio.h>
#include <pthread.h>
#include <sys/mman.h>

#ifndef MAP_NORESERVE
#define MAP_NORESERVE 0x4000   /* Linux, same on x86, arm and aarch64 */
#endif

static void *body(void *a) { return (void *)((long)a + 1); }

static int is_high(void *p) {
  return sizeof(void *) == 8 || ((unsigned long)p & 0x80000000UL) != 0;
}

int main(void) {
  int high = 0, i, ok = 0;
  /* Reserve only where mappings come out low (qemu-arm grows upward). A real
     32-bit kernel maps top-down from ~0xb6000000, where they are already
     high -- and a reservation there would push the next ones DOWN. */
  void *first = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (first == MAP_FAILED) { printf("probe failed\n"); return 1; }
  if (!is_high(first)) {
    void *reserve = mmap(0, 0x50000000UL, PROT_NONE,
                         MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (reserve == MAP_FAILED) { printf("reserve failed\n"); return 1; }
  }
  for (i = 0; i < 4; i++) {
    pthread_t t;
    void *r = 0;
    int rc = pthread_create(&t, 0, body, (void *)(long)(40 + i));
    if (rc != 0) { printf("create rc=%d\n", rc); return 1; }
    if (pthread_join(t, &r) != 0) { printf("join failed\n"); return 1; }
    if ((long)r == 41 + i) ok++;
  }
  {
    void *probe = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (probe != MAP_FAILED && is_high(probe)) high = 1;   /* 64-bit: always 1, the run itself is the check */
  }
  printf("threads ok %d, high mappings %d\n", ok, high);
  return 0;
}
