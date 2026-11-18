/* __int128 on x86-64 (rdx:rax, ir_codegen_i128.inc), against gcc's output.
   feature-c-int128-and-attribute-mode */
#include <stdio.h>
#include <stdint.h>
typedef unsigned __int128 u128;
typedef __int128 i128;
static void p(const char *n, u128 v){ printf("%s %016llx%016llx\n", n, (unsigned long long)(v >> 64), (unsigned long long)v); }
u128 gtab[3] = { 1, 0xFFFFFFFFFFFFFFFFull, 3 };
u128 gun[] = { 5, (u128)6 << 70 };
i128 g2d[2][2] = { {1, -2}, {3, 4} };
struct cfg { int id; u128 mask; } gcfg = { 4, 0xF0F0F0F0F0F0F0F0ull };
static const i128 gneg = -2;
u128 gbig = ((u128)1 << 100) + 5;
int main(void){
  u128 loc[3] = { 7, 8, (u128)9 << 64 }; i128 lun[] = { -1, 2, (i128)3 << 90 }; p("lun", (u128)lun[2]); printf("ln %d\n", (int)(sizeof lun / sizeof lun[0]));
  p("gun", gun[1]); printf("gn %d\n", (int)(sizeof gun / sizeof gun[0])); p("g2d", (u128)g2d[0][1]); p("g2d3", (u128)g2d[1][1]);
  p("g0", gtab[0]); p("g1", gtab[1]); p("g2", gtab[2]); p("cfg", gcfg.mask); printf("id %d\n", gcfg.id);
  p("gneg", (u128)gneg); p("gbig", gbig); p("l2", loc[2]);
  u128 x = (u128)1 << 80, z = 0; int n = 0;
  if (x && !z) n += 1; if (z || x) n += 2; if (z && x) n += 100;
  while (x) { x >>= 8; n++; }
  printf("n %d\n", n);
  i128 v = (i128)3 << 70; int c = (v == ((i128)3 << 70)) ? 5 : 6; printf("c %d\n", c);
  switch ((int)(v >> 70)) { case 3: printf("sw3\n"); break; default: printf("swd\n"); }
  u128 acc = 0; for (int i = 0; i < 10; i++) acc = acc * 10 + (u128)i; p("acc", acc);
  u128 *pp = &acc; *pp /= 7; p("div7", acc);
  long long sn = -9; i128 w = sn; p("w", (u128)w); unsigned un = 0xFFFFFFFFu; u128 wu = un; p("wu", wu);
  return 0; }
