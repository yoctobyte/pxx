/* A member taken straight off a struct-valued conditional: `(c ? a : b).f`.
 *
 * Found building dropbear 2026.94: libcrux's Eurydice_range_iter_next (in
 * libcrux_mlkem768_sha3.h, reached from mlkem768.c) is
 *
 *   ((it)->start == (it)->end) ? (Opt){.tag = None}
 *                              : (Opt){.tag = Some, .f0 = (it)->start++}
 *
 * and the caller writes `NEXT(&iter).tag == None`. pxx stopped with
 * `IR_UNSUPPORTED ... (kind 67)`: a conditional's value goes through a scalar
 * temp, which a struct does not fit. It is now read as `c ? a.f : b.f`.
 *
 * The rows check what that rewrite must keep: only the selected arm runs
 * (`start++` sits in one arm, and the loop count and the final `start` both
 * show an extra or missing increment), nested conditionals, a chained member
 * `.inner.v`, and plain struct variables as arms. The expected output is
 * gcc's.
 */
#include <stdio.h>
#include <stddef.h>

typedef enum { None, Some } tags;
typedef struct { tags tag; size_t f0; } Opt;
typedef struct { size_t start, end; } Range;
typedef struct { int v; } Inner;
typedef struct { int a; Inner inner; } Outer;

#define NEXT(it) (((it)->start == (it)->end) \
    ? ((Opt){.tag = None}) \
    : ((Opt){.tag = Some, .f0 = (it)->start++}))

int main(void)
{
  Range r = {1, 4};
  int n = 0;
  size_t sum = 0;
  Opt a = {Some, 5}, b = {None, 9};
  Outer x = {1, {10}}, y = {2, {20}}, z = {3, {30}};
  int k;

  while (NEXT(&r).tag != None)
    n++;
  printf("loop %d start %zu\n", n, r.start);

  r.start = 2;
  while (1) {
    Opt o = NEXT(&r);
    if (o.tag == None) break;
    sum += o.f0;
  }
  printf("sum %zu\n", sum);

  for (k = 0; k < 3; k++)
    printf("nested %zu chained %d\n",
           (k == 0 ? a : k == 1 ? b : (Opt){Some, 77}).f0,
           (k == 0 ? x : k == 1 ? y : z).inner.v);
  return 0;
}
