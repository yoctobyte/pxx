/* setjmp called through a function pointer, against gcc. On x86-64 the
 * indirect call parks the caller's rsp below the argument area, and the second
 * return (from longjmp) read it back after printf had reused that stack: a
 * segfault. It now lives in a frame slot per call site. The rest checks what
 * the change touches: alloca in the same body, indirect calls nested in
 * arguments, and a loop.
 * bug-c-a-setjmp-called-through-a-pointer-cannot-be-returned-to-on-x86-64 */
#include <stdio.h>
#include <setjmp.h>
#include <alloca.h>
#include <string.h>

static jmp_buf jb;
static int add(int a, int b) { return a + b; }
static int mul(int a, int b) { return a * b; }

static int viaptr(void) {
  int (*f)(jmp_buf) = setjmp;
  volatile int count = 0;
  int r = f(jb);
  printf("r=%d count=%d\n", r, count);
  count++;
  if (r < 3) longjmp(jb, r + 1);
  return count;
}

static int withalloca(int n) {
  int (*op)(int, int) = add;
  char *buf = alloca(n);
  memset(buf, 'x', n - 1);
  buf[n - 1] = 0;
  int s = op((int)strlen(buf), op(1, 2));
  char *buf2 = alloca(32);
  strcpy(buf2, "ok");
  return s + op((int)strlen(buf2), 0);
}

int main(void) {
  int (*ops[2])(int, int) = { add, mul };
  int i, acc = 0;
  printf("viaptr %d\n", viaptr());
  printf("nested %d\n", ops[1](ops[0](2, 3), ops[0](ops[1](2, 2), 1)));
  for (i = 0; i < 10; i++) acc = ops[i & 1](acc, i + 1);
  printf("loop %d\n", acc);
  printf("alloca %d\n", withalloca(20));
  return 0;
}
