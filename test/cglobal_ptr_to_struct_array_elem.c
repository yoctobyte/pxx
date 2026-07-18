/* Regression: a global pointer initialized to a struct-array element
   `static struct P *p = &g[1]` must use the RECORD size as the element stride,
   not the generic TypeSize(tyRecord)=8. pxx pointed 8 bytes in instead of
   sizeof(struct P), so `*p = ...` corrupted the wrong slot (csmith seed 9048).
   Exit 42. */
struct P { int a, b, c; };
static struct P g[3] = {{1,2,3},{4,5,6},{7,8,9}};
static struct P *p1 = &g[1];
static struct P *p2 = &g[2];
int main(void){
  if ((char*)p1 - (char*)&g[0] != (long)sizeof(struct P)) return 0;
  if ((char*)p2 - (char*)&g[0] != 2*(long)sizeof(struct P)) return 0;
  *p1 = g[0];                       /* g[1] := {1,2,3}; must not touch g[0]/g[2] */
  if (g[0].a==1 && g[0].c==3 && g[1].a==1 && g[1].c==3 && g[2].a==7 && g[2].c==9)
    return 42;
  return 0;
}
