/* Pointer-to-pointer parameter indexing must store full NULL/pointer values.
   Lua's tablerehash clears TString ** buckets through this shape. Exit 42. */
struct S { int v; struct S *next; };

static void clear(struct S **vect, int n) {
  int i;
  for (i = 0; i < n; i++)
    vect[i] = 0;
}

static void push(struct S **slot, struct S *x) {
  x->next = *slot;
  *slot = x;
}

int main(void) {
  struct S a;
  struct S b;
  struct S *bucket[4];
  struct S *p;
  int sum;

  bucket[0] = &a;
  bucket[1] = &b;
  bucket[2] = &a;
  bucket[3] = &b;
  clear(bucket, 4);
  if (bucket[0] != 0 || bucket[1] != 0 || bucket[2] != 0 || bucket[3] != 0)
    return 99;

  a.v = 19;
  b.v = 23;
  push(&bucket[2], &a);
  push(&bucket[2], &b);

  sum = 0;
  for (p = bucket[2]; p != 0; p = p->next)
    sum += p->v;

  return sum;
}
