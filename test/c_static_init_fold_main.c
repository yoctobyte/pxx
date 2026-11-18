#include <stdio.h>
struct desc { int off; const char *name; long c_off; long d_off; long y_off; };
struct fo { long flags; int cmp[8]; };
extern const struct desc init_d;
extern const struct fo init_f;
extern int (*init_p)(int);
int main(void)
{
  int i;
  printf("%d %s %ld %ld %ld\n", init_d.off, init_d.name, init_d.c_off, init_d.d_off, init_d.y_off);
  printf("%lx", (unsigned long)init_f.flags);
  for (i = 0; i < 8; i++) printf(" %d", init_f.cmp[i]);
  printf("\n%d\n", init_p(41));
  return 0;
}
