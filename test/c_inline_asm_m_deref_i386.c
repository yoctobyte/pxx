/* i386 inline asm: "m" INPUTS that are dereferences must name the object
   itself, not a copy of its value. Before the fix `addl $1, %0` and
   `addl %1, %0` with "m"(*p) added to a stack copy (k stayed 41, tot 100) and
   `movb $7, %0` set a copy (c stayed 1). A load through "m"(p[i]) read the
   copy's bytes, right by luck. (`lock` and a memory `inc` are refused by name
   on i386 -- the i386 text engine does not encode them.) Expected output is
   gcc -m32's.
   bug-c-an-m-operand-dereference-on-i386-still-binds-a-copy */
#include <stdio.h>
struct s { int a; int b[4]; } gs;
static int rd(int *p, int i) { int v; __asm__ volatile("movl %1, %0" : "=r"(v) : "m"(p[i])); return v; }
static int rdf(struct s *q) { int v; __asm__ volatile("movl %1, %0" : "=r"(v) : "m"(q->b[2])); return v; }
static void inc(int *p) { __asm__ volatile("addl $1, %0" : : "m"(*p) : "memory"); }
static void addto(int *p, int n) { __asm__ volatile("addl %1, %0" : : "m"(*p), "r"(n) : "memory"); }
static void setb(unsigned char *p) { __asm__ volatile("movb $7, %0" : : "m"(*p) : "memory"); }
int main(void)
{
  int arr[] = {5, 6, 7}; int k = 41; int tot = 100; unsigned char c = 1;
  gs.b[2] = 99;
  inc(&k); inc(&k); addto(&tot, 23); setb(&c);
  printf("%d %d %d %d %d\n", rd(arr, 2), rdf(&gs), k, tot, c);
  return 0;
}
