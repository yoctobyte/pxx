/* __attribute__((aligned(...))) whose argument is not a bare number.
   busybox's bzip2 declares `Bool inUse[256] ALIGNED(sizeof(long));` in its
   EState; pxx read the argument as digits only, got 0, and an alignment of 0
   made the whole struct opaque: every member access read 4 bytes at offset 0,
   and `busybox bzip2` crashed. Layout and accesses must match gcc's.
   bug-c-an-aligned-attribute-with-a-sizeof-argument-makes-the-struct-opaque */
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>

#define ALIGNED(m) __attribute__ ((__aligned__(m)))
typedef unsigned char Bool;

typedef struct {
  int a;
  void *p;
  char c1;
  Bool inUse[3] ALIGNED(sizeof(long));
  char c2;
  uint32_t v2 ALIGNED(2 * sizeof(int));
  char c3;
  double d ALIGNED(__alignof__(double));
  char c4;
  short s ALIGNED(0x10);
  char c5;
  int x ALIGNED((sizeof(void *)));
  uint32_t crc[256];
} ES;

static void fill(uint32_t *t, int e) { int i; for (i = 0; i < 256; i++) t[i] = i * e; }

int main(void) {
  ES *s = calloc(1, sizeof(ES));
  ES g;
  s->a = 5; s->inUse[2] = 7; s->v2 = 11; s->d = 2.5; s->s = 13; s->x = 17;
  fill(s->crc, 3);
  g = *s;
  printf("%d %d %u %g %d %d %u %u\n", s->a, s->inUse[2], s->v2, s->d, s->s, s->x,
         s->crc[10], g.crc[255]);
  printf("mod %d %d %d %d %d\n",
         (int)(offsetof(ES, inUse) % sizeof(long)),
         (int)(offsetof(ES, v2) % (2 * sizeof(int))),
         (int)(offsetof(ES, s) % 16),
         (int)(offsetof(ES, x) % sizeof(void *)),
         (int)(sizeof(ES) % 16));
  printf("crc@%d size %d\n", (int)offsetof(ES, crc), (int)sizeof(ES));
  return 0;
}
