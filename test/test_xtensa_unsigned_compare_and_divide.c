/* UNSIGNED 32-bit compare, divide and modulo on xtensa. The integer compare
 * arm branched SIGNED (blt/bge) for every operand type, and `/` `%` always used
 * quos/rems, so on xtensa a value >= 2^31 behaved as negative: crtl's sprintf
 * (cap = (size_t)-1) wrote nothing, 0xFFFFFFFFu / 2u was 0. riscv32 and every
 * other backend were right. Operands straddle 2^31 on purpose -- below it,
 * signed and unsigned agree and no row can fail. Compared against x86-64. */
#include <stdio.h>
#include <stddef.h>

static int lt(unsigned a, unsigned b) { return a < b; }
static int le(unsigned a, unsigned b) { return a <= b; }
static int gt(unsigned a, unsigned b) { return a > b; }
static int ge(unsigned a, unsigned b) { return a >= b; }

int main(void) {
  unsigned v[4] = { 1u, 0x7FFFFFFFu, 0x80000000u, 0xFFFFFFFFu };
  int i, j;
  size_t cap = (size_t)-1, o = 0;
  char buf[16];
  for (i = 0; i < 4; i++)
    for (j = 0; j < 4; j++)
      printf("%d%d%d%d", lt(v[i], v[j]), le(v[i], v[j]), gt(v[i], v[j]), ge(v[i], v[j]));
  printf("\n");
  printf("%u %u %u %u\n", v[3] / 2u, v[3] % 7u, v[2] / 3u, 3000000000u % 1000u);
  printf("%d\n", o + 1 < cap);
  sprintf(buf, "<%u>", v[3]);
  printf("%s\n", buf);
  return 0;
}
