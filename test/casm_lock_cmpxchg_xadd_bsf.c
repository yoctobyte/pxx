/* What the new inline-asm instructions DO, against gcc -O0. Their encodings
 * are checked against gas by test/casm_att_atomics_sysregs.att; this checks
 * the operand plumbing around them at run time.
 *
 * - lock cmpxchg, Gibux's futex/spinlock shape verbatim: "=a" output tied to
 *   an "0" input carrying the expected value. Both the success and the
 *   failure arm, because the failure arm is the one that writes eax.
 * - `lock;` with the instruction after the separator (the other gas spelling).
 * - lock xadd returns the OLD value in the register and adds into memory.
 * - lock inc/dec/or/and on memory.
 * - bsf/bsr in w/l/q, and sntrup761.c's bottom-bit idiom
 *   `bsfw %0,%0; cmovew %1,%0`, whose cmove covers bsf's undefined result
 *   on a zero source.
 *
 * Privileged or CPU-dependent instructions (str, sldt, sgdt, sidt, rdpid)
 * are not executed here: user mode may fault on them (UMIP), and rdpid is
 * missing on older CPUs. The gas oracle covers their bytes.
 */
#include <stdio.h>

static int cas(volatile int *p, int old, int nv)
{
  int prev;
  __asm__ volatile ("lock cmpxchgl %2, (%1)" : "=a"(prev) : "r"(p), "r"(nv), "0"(old) : "memory");
  return prev;
}

static long cas64(volatile long *p, long old, long nv)
{
  long prev = old;
  __asm__ volatile ("lock; cmpxchgq %2, (%1)" : "+a"(prev) : "r"(p), "r"(nv) : "memory", "cc");
  return prev;
}

static int fetch_add(volatile int *p, int d)
{
  __asm__ volatile ("lock xaddl %0, (%1)" : "+r"(d) : "r"(p) : "memory", "cc");
  return d;
}

static short bottombit(short x)
{
  short q, z;
  __asm__ ("bsfw %2,%0\n movw $16,%1\n cmovew %1,%0" : "=&r"(z), "=&r"(q) : "r"(x) : "cc");
  return z;
}

int main(void)
{
  volatile int w = 5;
  volatile long l = 100;
  unsigned v = 0x1200;
  unsigned long b = 0x8000000000000010UL;
  unsigned rl, fl;
  unsigned long rq;
  int r;

  r = cas(&w, 5, 9);
  printf("cas ok %d now %d\n", r, w);
  r = cas(&w, 5, 11);
  printf("cas miss %d now %d\n", r, w);
  rq = (unsigned long)cas64(&l, 100, -7);
  printf("cas64 %ld now %ld\n", (long)rq, l);
  rq = (unsigned long)cas64(&l, 100, 3);
  printf("cas64 miss %ld now %ld\n", (long)rq, l);

  r = fetch_add(&w, 4);
  printf("xadd old %d now %d\n", r, w);

  __asm__ volatile ("lock incl (%0)" :: "r"(&w) : "memory", "cc");
  __asm__ volatile ("lock; decq (%0)" :: "r"(&l) : "memory", "cc");
  __asm__ volatile ("lock orl %1, (%0)" :: "r"(&w), "r"(0x100) : "memory", "cc");
  __asm__ volatile ("lock andq %1, (%0)" :: "r"(&l), "r"(-4L) : "memory", "cc");
  printf("rmw %d %ld\n", w, l);

  __asm__ ("bsfl %1,%0" : "=r"(fl) : "r"(v) : "cc");
  __asm__ ("bsrl %1,%0" : "=r"(rl) : "r"(v) : "cc");
  __asm__ ("bsrq %1,%0" : "=r"(rq) : "r"(b) : "cc");
  printf("bsf %u bsr %u bsrq %lu\n", fl, rl, rq);
  printf("bottombit %d %d %d\n", bottombit(8), bottombit(-32768), bottombit(0));
  return 0;
}
