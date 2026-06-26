/* Nested anonymous union/struct members are laid out as sub-records, and the
   containing struct's fields stay contiguous (lua CallInfo/GCUnion; the emergent
   setobj-block failures in ldo/ltm). Exit 42. */
struct V { int val; };
struct CI {
  int tag;
  union { struct V *p; long x; } func;     /* pointer member of a union field */
  union { struct { int a, b; } l; long w; } u;
  int n;
};
int main(void) {
  struct V a[3];
  a[1].val = 20;
  struct CI ci;
  ci.tag = 0;
  ci.func.p = a;
  ci.u.l.a = 0; ci.u.l.b = 13;
  ci.n = 9;
  int viaPtr = (ci.func.p + 1)->val;       /* a[1].val = 20 */
  return viaPtr + ci.u.l.b + ci.n;         /* 20 + 13 + 9 = 42 */
}
