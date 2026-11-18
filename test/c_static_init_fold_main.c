#include <stdio.h>
struct desc { int off; const char *name; long c_off; long d_off; long y_off; };
struct fo { long flags; int cmp[8]; };
extern const struct desc init_d;
extern const struct fo init_f;
extern int (*init_p)(int);
struct protosw { int pr_type; };
struct domain { const struct protosw *sw, *swend; };
extern struct domain init_dom;
struct hvec { unsigned len; const void *base; };
extern const struct hvec init_hv, init_hv2;
int main(void)
{
  int i;
  printf("%d %s %ld %ld %ld\n", init_d.off, init_d.name, init_d.c_off, init_d.d_off, init_d.y_off);
  printf("%lx", (unsigned long)init_f.flags);
  for (i = 0; i < 8; i++) printf(" %d", init_f.cmp[i]);
  printf("\n%d\n", init_p(41));
  printf("%d %d %d\n", (int)(init_dom.swend - init_dom.sw), init_dom.sw[2].pr_type, init_dom.swend[-1].pr_type);
  printf("%u %.4s %d %d\n", init_hv.len, (const char *)init_hv.base,
         ((const short *)init_hv2.base)[0], ((const short *)init_hv2.base)[1]);
  return 0;
}
