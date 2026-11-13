/* Two inline-asm operand shapes dropbear 2026.94 needs, against gcc.
 *
 * 1. "+r" -- a read-write register operand. sntrup761.c's crypto_int16
 *    helpers verbatim (sarw/shrw/andw on a 16-bit value, and sarw by %cl).
 *    pxx turns each "+" output into the output plus a hidden input tied to
 *    it, numbered after every explicit operand as gcc numbers it. So the
 *    "c" input in int16_negative_mask_shift below is still %1, and a template
 *    that names it as %1 proves the numbering did not shift.
 *
 * 2. An ARRAY passed to an "r" input -- libtomcrypt's STORE32H/STORE64H,
 *    `"r"(seqbuf)` with `unsigned char seqbuf[4]`, used as `(%1)`. The array
 *    decays to its address. Sized as the array it got a 32-bit register and
 *    the template was refused; copied by value it would have carried the
 *    bytes. The row prints the stored bytes, so both mistakes are visible.
 *
 * The expected output is gcc -O0's on this file.
 */
#include <stdio.h>
#include <stdint.h>

typedef int16_t crypto_int16;

static crypto_int16 int16_negative_mask(crypto_int16 crypto_int16_x)
{
  __asm__ ("sarw $15,%0" : "+r"(crypto_int16_x) : : "cc");
  return crypto_int16_x;
}

static crypto_int16 int16_unsigned_topbit_01(crypto_int16 crypto_int16_x)
{
  __asm__ ("shrw $15,%0" : "+r"(crypto_int16_x) : : "cc");
  return crypto_int16_x;
}

static crypto_int16 int16_bottombit_01(crypto_int16 crypto_int16_x)
{
  __asm__ ("andw $1,%0" : "+r"(crypto_int16_x) : : "cc");
  return crypto_int16_x;
}

static crypto_int16 int16_shrmod(crypto_int16 crypto_int16_x, crypto_int16 crypto_int16_s)
{
  __asm__ ("andw $15,%1\n sarw %%cl,%0" : "+r"(crypto_int16_x), "+c"(crypto_int16_s) : : "cc");
  return crypto_int16_x;
}

/* "+r" alongside an explicit input that the template names by number. */
static uint64_t add_into(uint64_t acc, uint64_t v)
{
  __asm__ ("addq %1,%0" : "+r"(acc) : "r"(v) : "cc");
  return acc;
}

/* "+r" on a struct field: the lvalue is read before and written after. */
struct ctr { int pad; unsigned int n; };
static unsigned int bump(struct ctr *c)
{
  __asm__ ("addl $3,%0" : "+r"(c->n));
  return c->n;
}

#define STORE32H(x, y)           \
asm __volatile__ (               \
   "bswapl %0     \n\t"          \
   "movl   %0,(%1)\n\t"          \
   "bswapl %0     \n\t"          \
      ::"r"(x), "r"(y));

#define STORE64H(x, y)           \
asm __volatile__ (               \
   "bswapq %0     \n\t"          \
   "movq   %0,(%1)\n\t"          \
   "bswapq %0     \n\t"          \
   ::"r"(x), "r"(y): "memory");

int main(void)
{
  unsigned char seqbuf[4];
  unsigned char seq64[8];
  uint32_t seqno = 0x01020304u;
  uint64_t seq = 0x1122334455667788ull;
  struct ctr c = { 7, 40 };
  int i;

  printf("negmask %d %d\n", int16_negative_mask(-5), int16_negative_mask(5));
  printf("topbit %d %d\n", int16_unsigned_topbit_01(-5), int16_unsigned_topbit_01(5));
  printf("bottombit %d %d\n", int16_bottombit_01(7), int16_bottombit_01(8));
  printf("shrmod %d %d\n", int16_shrmod(-32768, 3), int16_shrmod(1024, 19));
  printf("add_into %llu\n", (unsigned long long)add_into(40, 2));
  printf("bump %u pad %d\n", bump(&c), c.pad);

  STORE32H(seqno, seqbuf);
  printf("store32h");
  for (i = 0; i < 4; i++) printf(" %02x", seqbuf[i]);
  printf(" seqno %08x\n", seqno);
  STORE64H(seq, seq64);
  printf("store64h");
  for (i = 0; i < 8; i++) printf(" %02x", seq64[i]);
  printf("\n");
  return 0;
}
