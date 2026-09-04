/* SPDX-License-Identifier: Zlib */
/* THE OTHER HALF OF THE CONFLICTING-TYPEDEF REFUSAL, and it is not padding.
 *
 * C11 6.7p3 permits a repeated typedef WHEN IT NAMES THE SAME TYPE, and real
 * headers lean on that constantly — a name defined identically in two headers
 * that both get included is ordinary, not an error. A refusal that fired on
 * these would be far worse than the silence it replaced, because it would
 * refuse code gcc accepts.
 *
 * So every row here is a repeat gcc compiles without complaint, and the file
 * exists to keep the check NARROW. Row 5 is the pointed part: an alias chain
 * that arrives at the same type by two different spellings is still the same
 * type, and must not be read as a conflict.
 *
 * gcc -O0 is the oracle at both widths; the transcript is width-independent.
 * bug-c-the-frontend-takes-the-last-of-two-conflicting-typedefs-silently
 */
#include <stdio.h>

typedef long T;
typedef long T;                    /* 1: identical scalar repeat */

typedef struct S S;
typedef struct S S;                /* 2: identical tagged-struct repeat */
struct S { int a, b; };

typedef unsigned int U;
typedef unsigned U;                /* 3: same type, different spelling */

typedef int (*FP)(int);
typedef int (*FP)(int);            /* 4: identical function-pointer repeat */

typedef T Alias;
typedef long Alias;                /* 5: alias chain reaching the same type */

static int twice(int v){ return v * 2; }

int main(void)
{
  struct S s; T t; U u; FP f; Alias a;
  s.a = 3; s.b = 4;
  t = 100; u = 7u; f = twice; a = 21;
  printf("1 %d\n", (int)(t + 1));
  printf("2 %d %d\n", s.a, s.b);
  printf("3 %u\n", u);
  printf("4 %d\n", f(5));
  printf("5 %d\n", (int)(a + 1));
  printf("6 %d\n", (int)(sizeof(T) == sizeof(Alias)));
  return 0;
}
