/* Pointer chains through a union field must remain acyclic and pointer-width.
   Lua's TString.u.hnext string-table buckets use this pattern. Exit 42. */
struct S {
  int v;
  union { struct S *next; long raw; } u;
};

int main(void) {
  struct S a;
  struct S b;
  struct S *bucket[4];
  struct S *p;
  int i;
  int sum;

  for (i = 0; i < 4; i++)
    bucket[i] = 0;

  a.v = 19;
  b.v = 23;
  a.u.next = bucket[2];
  bucket[2] = &a;
  b.u.next = bucket[2];
  bucket[2] = &b;

  sum = 0;
  for (p = bucket[2]; p != 0; p = p->u.next)
    sum += p->v;

  return sum;
}
