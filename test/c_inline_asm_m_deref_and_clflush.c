/* x86-64 inline asm (Gibux): clflush / clflushopt / clwb with a register-held
   address and with an "m" operand, and "m" INPUTS that are dereferences --
   which must name the object itself, not a copy of its value. Before the fix
   `lock incl %0` with "m"(*p) incremented a stack copy (k stayed 41) and
   clflush flushed a temporary. Expected output is gcc's.
   bug-c-an-m-operand-that-is-a-dereference-binds-a-copy */
#include <stdio.h>
struct s { int a; long b[4]; } gs;
static char line[128];
static void fl_r(void *p) { __asm__ volatile("clflush (%0)" : : "r"(p) : "memory"); }
static void fl_m(void *p) { __asm__ volatile("clflush %0" : : "m"(*(volatile char *)p)); }
static void wb(void *p) { __asm__ volatile("clwb 8(%0)" : : "r"(p) : "memory"); }
static long rd(long *p, int i) { long v; __asm__ volatile("movq %1, %0" : "=r"(v) : "m"(p[i])); return v; }
static long rdf(struct s *q) { long v; __asm__ volatile("movq %1, %0" : "=r"(v) : "m"(q->b[2])); return v; }
static void inc(int *p) { __asm__ volatile("lock incl %0" : : "m"(*p) : "memory"); }
static void addto(long *p, long n) { __asm__ volatile("lock addq %1, %0" : : "m"(*p), "r"(n) : "memory"); }
int main(int argc, char **argv)
{
  long arr[] = {5, 6, 7}; int k = 41; long tot = 100;
  line[0] = 'x';
  (void)argv;
  fl_r(line); fl_m(line + 64);
  if (argc > 99) wb(line);   /* assembled, not run: clwb is missing on older CPUs (plexus's E5-2620 v2) */
  gs.b[2] = 99;
  inc(&k); inc(&k); addto(&tot, 23);
  printf("%c %ld %ld %d %ld\n", line[0], rd(arr, 2), rdf(&gs), k, tot);
  return 0;
}
