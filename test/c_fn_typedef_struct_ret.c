/* A function TYPE typedef returning a struct pointer (NetBSD if_llatbl.h):
   `typedef struct e *(lk_t)(...)` and the unparenthesised spelling, called
   through a member and a parameter, inside parentheses and as an argument.
   Also a by-value struct return through the same shape. */
#include <stdio.h>

struct t;
struct e { int a, b; };
typedef struct e *(lk_t)(struct t *, unsigned flags, const void *k);
typedef struct e *lk2_t(int);
typedef struct e val_t(int);
struct t { int z; lk_t *lk; lk2_t *lk2; val_t *val; };

static struct e tab[3] = { {1, 10}, {2, 20}, {3, 30} };
static struct e *look(struct t *t, unsigned flags, const void *k) { return &tab[(t->z + flags + *(const int *)k) % 3]; }
static struct e *look2(int i) { return &tab[i]; }
static struct e val(int i) { struct e r = tab[i]; r.b += 100; return r; }
static int show(struct e *p) { return p->a * 1000 + p->b; }
static struct e *call(lk2_t *f, int i) { return (f(i)); }

int main(void)
{
  struct t t = { 1, look, look2, val };
  int k = 1;
  struct e *p = (t.lk(&t, 0, &k));
  printf("%d %d %d\n", p->a, show(t.lk(&t, 1, &k)), (t.lk2(0))->b);
  printf("%d %d %d\n", show(call(look2, 2)), t.val(1).b, (t.val(2)).a);
  return 0;
}
