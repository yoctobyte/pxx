/* `&` of an array-typed struct field (which already decays to its address) was
   producing a double address-of that IRLowerAddress could not lower. lua hits
   this (lmem.c/ldebug.c). Exit 42. */
struct S { int v[3]; };
int g(struct S *s) { int *p = (int *)&s->v; return p[0] + p[2]; }   /* arrow form */
int h(struct S *s) { int *p = (int *)&s->v; return p[1]; }
int main(void) {
  struct S s;
  s.v[0] = 30; s.v[1] = 0; s.v[2] = 12;
  return g(&s) + h(&s);   /* (30+12) + 0 = 42 */
}
