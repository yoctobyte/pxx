/* A field at offset 0 and `x + 0` emit no instruction on x86-64 (row
 * c_noaddzero26 counts `add/sub $0x0,%rax`; the Rainyday pc kernel had 3132).
 * The values must still be right, against gcc.
 * feature-c-toybox-size-gap-literal-headers-call-realign-no-regalloc */
#include <stdio.h>
struct node { int key; struct node *next; long val; };
struct outer { struct node first; int tail; };
static int sum(const struct node *p) {
  int s = 0;
  for (; p; p = p->next) s += p->key;
  return s;
}
int main(void) {
  struct node c = { 3, 0, 30 }, b = { 2, &c, 20 }, a = { 1, &b, 10 };
  struct outer o = { { 7, 0, 70 }, 8 };
  struct outer *po = &o;
  int arr[4] = { 5, 6, 7, 8 };
  int *q = arr + 0;
  long z = 0, x = 41;
  a.key += 10; po->first.key = po->first.key + 0;
  printf("%d %d %d %ld\n", sum(&a), po->first.key, po->tail, a.next->next->val);
  printf("%d %d %ld %ld\n", q[0], *(arr + 0), x + z, (x | 0) ^ 0);
  return 0;
}
