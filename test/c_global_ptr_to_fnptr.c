/* A GLOBAL pointer to a function pointer, `int (**ops)(void *)` (NetBSD's
   VOCALL: `(*((ops)[(off)]))(v)`), called in every spelling, inside
   parentheses and as an argument. */
#include <stdio.h>

static int dbl(void *v) { return *(int *)v * 2; }
static int neg(void *v) { return -*(int *)v; }
static int sq(void *v) { return *(int *)v * *(int *)v; }
static int (*vec[3])(void *) = { dbl, neg, sq };
int (**ops)(void *) = vec;
extern int (**ops2)(void *);
int (**ops2)(void *) = vec + 1;

static int id(int x) { return x; }

int main(void)
{
  int v = 7, off = 2;
  printf("%d %d %d\n", (( *((ops)[(off)])) (&v)), id((*ops)(&v)), (ops[1](&v)));
  printf("%d %d %d\n", id((**ops2)(&v)), ((*(ops2 + 1))(&v)), id(ops2[0](&v)));
  return 0;
}
