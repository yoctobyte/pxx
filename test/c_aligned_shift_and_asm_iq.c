/* `__aligned((1 << 6))` (FreeBSD's CACHE_LINE_SIZE) is 64, not the 16 pxx fell
   back to; and the "iq" asm constraint (immediate or byte register) that
   FreeBSD's atomic_set_char uses. bug-c-aligned-with-a-shifted-argument-falls-back-to-16,
   bug-c-inline-asm-constraint-iq-is-unsupported. Expected output is gcc's. */
#include <stdio.h>
#include <stddef.h>

#define CACHE_LINE_SHIFT 6
#define CACHE_LINE_SIZE (1 << CACHE_LINE_SHIFT)
struct pcpu_lock { int owner; } __attribute__((__aligned__(CACHE_LINE_SIZE)));
struct holder { char tag; struct pcpu_lock l; char after; };
struct twice { long x; } __attribute__((aligned(2 * (1 << 3))));
struct mixed { char c; } __attribute__((aligned(sizeof(int) << 2)));

static inline void set_char(volatile unsigned char *p, unsigned char v) {
  __asm__ __volatile__("lock; orb %b1,%0" : "+m" (*p) : "iq" (v) : "cc");
}
static inline void clear_char(volatile unsigned char *p) {
  __asm__ __volatile__("lock; andb %b1,%0" : "+m" (*p) : "iq" ((unsigned char)~0x01) : "cc");
}

int main(void) {
  volatile unsigned char c = 0x10;
  unsigned char v = 0x03;
  printf("pcpu_lock %zu/%zu holder %zu l@%zu after@%zu\n", sizeof(struct pcpu_lock),
         _Alignof(struct pcpu_lock), sizeof(struct holder), offsetof(struct holder, l),
         offsetof(struct holder, after));
  printf("twice %zu/%zu mixed %zu/%zu\n", sizeof(struct twice), _Alignof(struct twice),
         sizeof(struct mixed), _Alignof(struct mixed));
  set_char(&c, v);
  printf("set %#x\n", c);
  clear_char(&c);
  printf("clear %#x\n", c);
  return 0;
}
