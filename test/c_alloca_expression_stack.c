/* SPDX-License-Identifier: Zlib */
/*
 * alloca() reached with a value already on the EXPRESSION STACK.
 *
 * The x86-64 and aarch64 value models keep live values on the machine stack --
 * `push rax` / `pop rax`, `str x0,[sp,#-16]!` / `ldr x0,[sp],#16` -- and
 * IR_ALLOCA lowered the stack pointer under them. So anything pushed before an
 * alloca and popped after read the alloca'd hole instead of its own value:
 *
 *     long b = a + (long)(unsigned long)(alloca(32) != 0);   // row 9
 *
 * printed 1 rather than 101 on both targets. This is NOT the argument-list
 * shape that cparser.inc's CHoistAllocaArgs covers (that one is
 * c_alloca_in_call_argument.c) -- row 9 has no call in it at all, which is why
 * the frontend hoist could not see it and why the fix is in the backends: the
 * hole is carved at the bottom of the fixed frame and the live region between
 * the stack pointer and the alloca base is relocated down to make room.
 *
 * Every row is a differential against gcc -O0 on this same file. Rows 1-8 are
 * the realistic shapes that were ALREADY correct -- they are here as the
 * controls that a "fix" must not break, not as regressions. Rows 10-12 and
 * 15-17 are the shapes CReplaceAllocasWithTemps deliberately does not walk
 * (statement expression, ternary/&& , an indirect call's callee expression);
 * measured, they were already correct too, and they stay here because the
 * whitelist that skips them is still there.
 *
 * Row 6 must keep three allocations distinct AND live at once; row 8 the same
 * within one declaration. Those are the rows that catch a fix which merely
 * stops the corruption by handing back memory the next alloca overwrites.
 *
 * bug-a-alloca-inside-a-call-argument-list-corrupts-the-restored-stack-pointer
 */
#include <alloca.h>
#include <stdio.h>
#include <string.h>

static int sink(void *p) { return p != 0; }
static long add3(long a, long b, long c) { return a + b + c; }

struct S { char *q; long n; };

int main(void) {
  long n = 32;

  /* 1. declaration with initializer */
  { char *p = alloca(n); memset(p, 'a', 4); p[4] = 0; printf("1 %s %d\n", p, sink(p)); }

  /* 2. plain assignment */
  { char *p; p = alloca(n); memset(p, 'b', 4); p[4] = 0; printf("2 %s\n", p); }

  /* 3. pointer arithmetic on the result */
  { char *p = (char *)alloca(n) + 8; memset(p, 'c', 4); p[4] = 0; printf("3 %s\n", p); }

  /* 4. assignment through a struct field */
  { struct S s; s.q = alloca(n); s.n = n; memset(s.q, 'd', 4); s.q[4] = 0; printf("4 %s %ld\n", s.q, s.n); }

  /* 5. as a call argument */
  { printf("5 %d\n", sink(alloca(n))); }

  /* 6. inside a loop, three distinct live allocations */
  { char *v[3]; int i; for (i = 0; i < 3; i++) { v[i] = alloca(16); v[i][0] = 'p' + i; v[i][1] = 0; }
    printf("6 %s %s %s %d %d\n", v[0], v[1], v[2], v[0] != v[1], v[1] != v[2]); }

  /* 7. in a ternary arm */
  { char *p = n > 0 ? (char *)alloca(n) : (char *)0; memset(p, 'e', 4); p[4] = 0; printf("7 %s\n", p); }

  /* 8. two allocas in one declaration */
  { char *p = alloca(n), *q = alloca(n); memset(p, 'f', 4); p[4] = 0; memset(q, 'g', 4); q[4] = 0;
    printf("8 %s %s %d\n", p, q, p != q); }

  /* 9. THE REGRESSION: a value on the expression stack across the alloca */
  { long a = 100; long b = a + (long)(unsigned long)(alloca(32) != 0); printf("9 %ld\n", b); }

  /* 10. statement expression in an argument */
  { char *p = 0; printf("10 %ld\n", add3(1, 2, ({ int i; for (i = 0; i < 3; i++) { p = alloca(4); } (long)(p != 0); }))); }

  /* 11. ternary / && inside an argument */
  { printf("11 %ld %ld\n", add3(10, 20, n > 0 ? (long)(alloca(16) != 0) : 0L),
                           add3(10, 20, (n > 0 && alloca(16) != 0) ? 7L : 0L)); }

  /* 12. alloca in the callee expression of an indirect call */
  { long (*t)(long,long,long) = add3; printf("12 %ld\n", (alloca(16) ? t : t)(1, 2, 3)); }

  /* 13. C99 VLA, which lowers to the same op */
  { int m = 5; char vla[m]; int i; for (i = 0; i < m; i++) vla[i] = 'A' + i; vla[m-1] = 0;
    printf("13 %s %d\n", vla, m); }

  /* 14. row 9 again, but inside an argument list, where the hoist DOES reach */
  { long a = 41; printf("14 %ld\n", a + (long)(unsigned long)(alloca(48) != 0)); }

  /* 15. ternary arm holding an alloca, directly in an EXTERNAL call's arg list */
  printf("15 %ld\n", n > 0 ? (long)(unsigned long)(alloca(16) != 0) : 0L);

  /* 16. statement expression holding an alloca, same position */
  printf("16 %ld\n", ({ char *p = alloca(16); (long)(unsigned long)(p != 0); }));

  /* 17. the stack-ARGUMENT path: nine arguments, alloca in a ternary arm */
  printf("17 %ld %ld %ld %ld %ld %ld %ld %ld\n", 1L, 2L, 3L, 4L, 5L, 6L,
         n > 0 ? (long)(unsigned long)(alloca(64) != 0) : 0L, 8L);

  return 0;
}
