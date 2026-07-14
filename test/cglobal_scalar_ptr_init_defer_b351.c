/* Scalar pointer-global initializers the fast paths can't fold — a cast
   `(char*)&g`, `&struct.field`, pointer arithmetic `arr + 1` — used to be
   silently SKIPPED: the pointer read back null and the first dereference died
   (csmith seed 3's crash family, b351). They now defer to a replay at main,
   like the aggregate walker. The foldable forms (&g, &arr[k], "str") must keep
   working through their fast paths. */
#include <stdio.h>

static int g = 7;
static char gc = 3;
struct S { int a; char b; };
static struct S st = {1, 2};
static int arr[3] = {4, 5, 6};

static char *p1 = (char *)&g;             /* cast + address-of */
static char *p2 = &gc;                    /* plain & (fast path) */
static int *p3 = &st.a;                   /* &struct.field */
static char *p4 = &st.b;                  /* &struct.field, non-zero offset */
static int *p5 = arr + 1;                 /* pointer arithmetic */
static int *p6 = &arr[2];                 /* &arr[k] (fast path) */
static const volatile char *p7 = &gc;     /* qualifiers */
static char *p8 = "lit";                  /* string literal (fast path) */

int main(void) {
  printf("%d %d %d %d %d %d %d %s\n", p1 ? *p1 : -1, p2 ? *p2 : -1,
         p3 ? *p3 : -1, p4 ? *p4 : -1, p5 ? *p5 : -1, p6 ? *p6 : -1,
         p7 ? *p7 : -1, p8);
  return 0;
}
