/* SPDX-License-Identifier: Zlib */
/*
 * A PARAMETER DECLARED WITH FUNCTION TYPE is adjusted to pointer-to-function
 * (C 6.7.5.3p8). It is the sibling of the array adjustment `T a[]` -> `T *a`,
 * which this frontend already did; this one was missing, so the parameter list
 * after the name was left unconsumed, the parameter kept the RETURN type, and
 * a call through it in the body was "call to undeclared function".
 *
 * Not a curiosity: busybox's libbb/procps.c declares
 *   static char* get_cached(int ug, uid_t id, char* FAST_FUNC x2x_utoa(uid_t))
 * which is the ordinary way to write a callback parameter without a typedef,
 * and it is what found this.
 *
 * ROWS 5 AND 6 ARE THE POSITIVE CONTROL, and they are the point of the file
 * being one file: the pointer spelling `int (*f)(int)` and the array
 * adjustment `int a[]` go through the SAME code the function spelling now
 * shares. If a change breaks the shared parser, these fail too -- and if they
 * pass while rows 1-4 fail, the sharing was not real.
 *
 * Every row is asserted against gcc's output for this same source.
 *
 * feature-c-corpus-busybox-multi-applet
 */
#include <stdio.h>

static int twice(int x) { return x + x; }
static int negate(int x) { return -x; }
static const char *namer(unsigned id) {
  static char b[16];
  sprintf(b, "u%u", id);
  return b;
}

/* 1: the bare shape. */
static int apply(int v, int f(int)) { return f(v); }

/* 2: two of them in one list, and one of them after an ordinary parameter. */
static int apply2(int v, int f(int), int g(int)) { return f(v) + g(v); }

/* 3: a pointer return type, which is what busybox's case looks like -- the
   parameter's own type is `char *(*)(unsigned)`, not `char *`. */
static const char *lookup(unsigned id, const char *nm(unsigned)) { return nm(id); }

/* 4: a variadic one, so the adjusted signature has to carry `...` too. */
static int viaprintf(int n, int p(const char *, ...)) {
  return p("v%d\n", n);
}

/* 5: the pointer spelling of row 1 -- must still work. */
static int apply_ptr(int v, int (*f)(int)) { return f(v); }

/* 6: the array adjustment, the other arm of the same rule. */
static int sum(int a[], int n) { int i, s = 0; for (i = 0; i < n; i++) s += a[i]; return s; }

int main(void) {
  int arr[4];
  arr[0] = 1; arr[1] = 2; arr[2] = 3; arr[3] = 4;
  printf("1 %d\n", apply(21, twice));
  printf("2 %d\n", apply2(10, twice, negate));
  printf("3 %s\n", lookup(7, namer));
  printf("4 %d\n", viaprintf(9, printf) > 0);
  printf("5 %d\n", apply_ptr(21, twice));
  printf("6 %d\n", sum(arr, 4));
  return 0;
}
