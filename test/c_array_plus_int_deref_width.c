/* `*(arr + n)` and `(arr + n)[k]` have the ARRAY's element type.
 *
 * pxx typed `arr + n` by asking whether an operand was a pointer, and an
 * array is not one until it decays, so the pointee defaulted to int: a byte
 * store wrote four bytes and a byte load read four. libtomcrypt's portable
 * STORE64H (`(y)[7] = ...` with y = md->sha512.buf + 120) zeroed three bytes
 * past the hash state, which was dropbear's local `hash_desc` on aarch64.
 *
 * Every array spelling (local, global, member via . and ->, through a union,
 * int + arr, arr - 0), loads and stores, 1/2/8-byte elements, each with a
 * guard after the array. Output must equal gcc's.
 */
#include <stdio.h>
#include <string.h>

typedef unsigned long long u64;
struct st { long n; unsigned char buf[8]; unsigned guard; };
struct sh { short sb[4]; unsigned guard; };
struct sq { u64 qb[2]; unsigned guard; };
union un { struct st s; char pad[32]; };

unsigned char gb[8];
unsigned gguard;

#define STORE64H(x, y)                                                                     \
do { (y)[0] = (unsigned char)(((x)>>56)&255); (y)[1] = (unsigned char)(((x)>>48)&255);     \
     (y)[2] = (unsigned char)(((x)>>40)&255); (y)[3] = (unsigned char)(((x)>>32)&255);     \
     (y)[4] = (unsigned char)(((x)>>24)&255); (y)[5] = (unsigned char)(((x)>>16)&255);     \
     (y)[6] = (unsigned char)(((x)>>8)&255); (y)[7] = (unsigned char)((x)&255); } while(0)

static void store_arrow(struct st *p) { (p->buf + 4)[3] = 0; *(p->buf + 6) = 0; }
static void store_union(union un *u) { STORE64H(0x0102030405060708ULL, u->s.buf + 0); }
static int load_arrow(struct st *p) { return *(p->buf + 7) + (p->buf + 4)[2]; }

int main(void) {
  struct st x; union un u; struct sh h; struct sq q;
  unsigned char lb[8];
  unsigned lguard;
  int i;

  memset(&x, 0xab, sizeof x); x.guard = 0x11223344;
  store_arrow(&x);
  printf("store arrow guard %x buf6 %d buf7 %d\n", x.guard, x.buf[6], x.buf[7]);

  memset(&u, 0xab, sizeof u); u.s.guard = 0x55667788;
  store_union(&u);
  printf("store union guard %x", u.s.guard);
  for (i = 0; i < 8; i++) printf(" %d", u.s.buf[i]);
  printf("\n");

  for (i = 0; i < 8; i++) x.buf[i] = (unsigned char)(i + 1);
  x.guard = 0xffffffff;
  printf("load arrow %d member %d %d\n", load_arrow(&x), *(x.buf + 7), (4 + x.buf)[3]);

  for (i = 0; i < 8; i++) { lb[i] = (unsigned char)(10 + i); gb[i] = (unsigned char)(20 + i); }
  lguard = 0x99999999; gguard = 0x77777777;
  *(lb + 7) = 1; (gb + 4)[3] = 2; *(lb - 0) = 3;
  printf("local %d %d global %d guards %x %x\n", lb[7], *(lb - 0), *(gb + 7), lguard, gguard);

  memset(&h, 0xab, sizeof h); h.guard = 0x12345678;
  *(h.sb + 3) = -2;
  printf("short %d guard %x size %d\n", *(h.sb + 3), h.guard, (int)sizeof(*(h.sb + 1)));

  memset(&q, 0xab, sizeof q); q.guard = 0x0badf00d;
  *(q.qb + 1) = 0x8000000000000001ULL;
  printf("u64 %llx guard %x size %d\n", *(q.qb + 1), q.guard, (int)sizeof(*(q.qb + 1)));

  printf("sizes %d %d %d %d\n", (int)sizeof(*(lb + 4)), (int)sizeof(*(gb + 4)),
         (int)sizeof(*(x.buf + 4)), (int)sizeof((x.buf + 4)[3]));
  return 0;
}
