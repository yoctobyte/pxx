/* A bit-field after a function-pointer member or an inline struct member,
 * against gcc. The bit cursor did not move past those members, so the
 * bit-field went back to bit 0 and overlaid them. micropython's mp_stream_p_t
 * ends `read, write, ioctl` function pointers with `is_text : 1`, and every
 * stream read jumped to read+1.
 * bug-c-a-bit-field-after-a-function-pointer-or-inline-struct-member-overlays-it */
#include <stdio.h>
#include <stddef.h>

typedef unsigned long uint_t;
static uint_t rd(void *o, uint_t n) { (void)o; return n + 100; }
static uint_t wr(void *o, uint_t n) { (void)o; return n + 200; }

typedef struct { uint_t (*read)(void *, uint_t); uint_t (*write)(void *, uint_t); void *ioctl; uint_t is_text : 1; } P;
typedef struct { unsigned x : 3; void (*f[2])(void); unsigned b : 2; char tail; } A;
typedef struct { unsigned x : 3; struct { int p, q; } s; unsigned b : 2; char tail; } N;
typedef struct { char c; struct { int p; }; unsigned b : 1; unsigned d : 7; char tail; } U;

static const P sp = { rd, wr, 0, 1 };

int main(void) {
  P lp = { rd, wr, 0, 1 };
  A a; N n; U u;
  printf("P %d %d %lu %lu %d %lu %lu\n", (int)sizeof(P), (int)sp.is_text,
         sp.read(0, 1), sp.write(0, 1), (int)lp.is_text, lp.read(0, 2), lp.write(0, 2));
  a.x = 5; a.f[0] = 0; a.f[1] = 0; a.b = 3; a.tail = 'A';
  printf("A %d %d %d %d %d %c\n", (int)sizeof(A), (int)offsetof(A, tail), (int)a.x, a.f[0] == 0 && a.f[1] == 0, (int)a.b, a.tail);
  n.x = 6; n.s.p = 11; n.s.q = 22; n.b = 2; n.tail = 'N';
  printf("N %d %d %d %d %d %d %c\n", (int)sizeof(N), (int)offsetof(N, tail), (int)n.x, n.s.p, n.s.q, (int)n.b, n.tail);
  u.c = 'c'; u.p = 33; u.b = 1; u.d = 99; u.tail = 'U';
  printf("U %d %d %c %d %d %d %c\n", (int)sizeof(U), (int)offsetof(U, tail), u.c, u.p, (int)u.b, (int)u.d, u.tail);
  return 0;
}
