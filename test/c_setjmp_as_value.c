/* setjmp and longjmp as VALUES, and jmp_buf passed to functions, against gcc.
 *
 * glibc's setjmp is a real function, and micropython's native emitter puts it
 * in a table of function pointers (py/nativeglue.c); pxx's setjmp was a macro
 * only, so a bare `setjmp` was an undeclared identifier
 * (bug-c-setjmp-cannot-be-used-as-a-function-value). jmp_buf is now glibc's
 * array of one struct, so a function given a `jmp_buf env` gets the caller's
 * buffer, not a copy.
 *
 * Not covered: a setjmp called through a pointer FROM C and then longjmp'd
 * back to. On x86-64 that loses the call's saved stack pointer
 * (bug-c-a-setjmp-called-through-a-pointer-cannot-be-returned-to-on-x86-64). */
#include <stdio.h>
#include <setjmp.h>
#include <signal.h>

typedef int (*sjfn)(jmp_buf);
typedef void (*ljfn)(jmp_buf, int);

static jmp_buf jb, jb2;
static sigjmp_buf sjb;
static volatile int hits;

static void jump_via(jmp_buf e, int v) { longjmp(e, v); }
static void jump_ptr(ljfn f, jmp_buf e, int v) { f(e, v); }
static void sigjump_via(sigjmp_buf e, int v) { siglongjmp(e, v); }

struct holder { int before; jmp_buf env; int after; };

int main(void) {
  sjfn f = setjmp;
  ljfn lj = longjmp;
  void *table[] = { (void *)setjmp, (void *)longjmp, (void *)0 };
  struct holder h;
  volatile int r;

  printf("table %d %d %d\n", table[0] == (void *)f, table[1] == (void *)lj, table[0] != table[1]);
  printf("pointer call first return %d\n", f(jb2));

  r = setjmp(jb);
  hits++;
  if (r == 0) jump_via(jb, 4);
  else if (r == 4) jump_ptr(lj, jb, 7);
  else if (r == 7) longjmp(jb, 0);
  printf("chain r=%d hits=%d\n", (int)r, (int)hits);

  h.before = 11; h.after = 22;
  r = setjmp(h.env);
  if (r == 0) jump_via(h.env, 3);
  printf("struct field r=%d %d %d\n", (int)r, h.before, h.after);

  r = sigsetjmp(sjb, 1);
  if (r == 0) sigjump_via(sjb, 5);
  printf("sigsetjmp r=%d\n", (int)r);
  return 0;
}
