/* A block-scope `static` must stay static when another storage class sits
   between it and the type.
   bug-c-a-block-scope-static-is-silently-dropped-when-a-thread-storage-class-precedes-the-type

   THE FAILURE WAS NOT ABOUT THREADS. `static __thread int f;` compiled to an
   ORDINARY STACK LOCAL: the dispatcher read `static`, consumed it, tested for a
   type token, met `__thread` instead, and fell through with the static-ness
   already thrown away. The `__thread` merely stood in the way. Single-threaded,
   x86-64, the default target, no diagnostic.

   EVERY ROW HERE MUST BE CALLED MORE THAN ONCE, AND THAT IS THE WHOLE DESIGN.
   A discarded static and a real static agree on the FIRST call, so a one-call
   probe reports success on the broken compiler — it did, during the
   investigation, and `= 0` was written off as working because 0 is also what a
   fresh stack local holds. The rows only discriminate from the second call on.

   THE DEEPER-FRAME ROW IS THE ONE THAT CANNOT BE FAKED. Calling through a
   recursion that pushes a 512-byte frame moves the stack, so a stack local is
   re-created at a different address and its count restarts, while a static
   keeps counting. It does not depend on optimisation level or on any value
   being distinctive.

   Values are chosen so no row can pass by collision: the seeded rows start at 5
   and 100, never 0 or 1.

   AND THE `bare` ROW IS THE WEAKEST ONE ON PURPOSE — IT CAN PASS ON A BROKEN
   COMPILER. Measured while writing this: standalone, the unfixed compiler
   returned 4388880/4388881/4388882 for it, but inside THIS file the same
   declaration returned 1/2/3, because the stack slot it wrongly landed on
   happened to hold 0. Uninitialised stack memory is zero far too often for a
   no-initialiser row to be a reliable discriminator. It is kept because it is
   the shape users actually write, and the verdict does not rest on it: `zero`,
   `seed`, `deeper` and `back` all failed on the unfixed compiler in the same
   run, and `deeper` cannot be faked by any value that happens to be in memory.

   BOTH SPELLINGS, VALID ORDER ONLY. `__thread static` (specifier before
   `static`) is REFUSED by gcc — "'__thread' before 'static'" — so it is not in
   this file: pxx accepts it, which is leniency and not a defect, but a row gcc
   cannot compile would cost this file its oracle. */
#include <stdio.h>

static int bump_bare(void)  { static __thread int f;      f++; return f; }
static int bump_zero(void)  { static __thread int f = 0;  f++; return f; }
static int bump_seed(void)  { static __thread int f = 5;  f++; return f; }
static int bump_c11(void)   { static _Thread_local int f = 100; f++; return f; }
static int bump_plain(void) { static int f;              f++; return f; }

/* pad the frame so a stack slot cannot land where it did at the shallow depth */
static int deeper(int d) { char pad[512]; if (d) { pad[0] = (char)d; return deeper(d - 1) + pad[0] * 0; } return bump_bare(); }

int main(void) {
  int fails = 0;
  int a, b, c;

  a = bump_bare(); b = bump_bare(); c = bump_bare();
  if (a != 1 || b != 2 || c != 3) { printf("FAIL bare: %d %d %d\n", a, b, c); fails++; }

  a = bump_zero(); b = bump_zero();
  if (a != 1 || b != 2) { printf("FAIL zero: %d %d\n", a, b); fails++; }

  a = bump_seed(); b = bump_seed();
  if (a != 6 || b != 7) { printf("FAIL seed: %d %d\n", a, b); fails++; }

  a = bump_c11(); b = bump_c11();
  if (a != 101 || b != 102) { printf("FAIL c11: %d %d\n", a, b); fails++; }

  a = bump_plain(); b = bump_plain();
  if (a != 1 || b != 2) { printf("FAIL plain-control: %d %d\n", a, b); fails++; }

  /* bump_bare has been called 3 times; from a deeper frame it must continue */
  a = deeper(3);
  if (a != 4) { printf("FAIL deeper: %d (a stack slot restarts here)\n", a); fails++; }
  b = bump_bare();
  if (b != 5) { printf("FAIL back: %d\n", b); fails++; }

  if (!fails) printf("block static survives a storage class: 6 rows OK\n");
  return fails != 0;
}
