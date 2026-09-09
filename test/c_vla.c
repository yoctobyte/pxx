/* C variable-length arrays, lowered through alloca (feature-c-vla-via-alloca).
   The loop shape is the one that used to stop after two iterations: a VLA sized
   at a silent ZERO sat on top of the next stack slot, so writing through it
   clobbered the loop's own counter (bug-cfront-vla-stack-corruption).
   Every number here is gcc's answer on the same source. */
#include <stdio.h>
#include <string.h>

struct pt { int x, y; };

int vla_sum(int n)
{
  int arr[n];
  int i, s = 0;
  for (i = 0; i < n; i++) arr[i] = i * 3;
  for (i = 0; i < n; i++) s += arr[i];
  return s;
}

/* sizeof on a VLA is a RUNTIME value, not the pointer size. */
int vla_bytes(int n)
{
  char buf[n + 1];
  buf[0] = 'a';
  return (int)sizeof(buf);
}

int vla_int_bytes(int n)
{
  int arr[n];
  arr[0] = 0;
  return (int)sizeof(arr);
}

/* an expression dimension, and a record element (stride = RecSize) */
int vla_pts(int n)
{
  struct pt ps[n * 2];
  int i, s = 0;
  for (i = 0; i < n * 2; i++) { ps[i].x = i; ps[i].y = i + 1; }
  for (i = 0; i < n * 2; i++) s += ps[i].x + ps[i].y;
  return s;
}

/* a VLA of pointers */
int vla_ptrs(int n)
{
  int *ps[n];
  int a = 7, b = 11, i, s = 0;
  for (i = 0; i < n; i++) ps[i] = (i & 1) ? &b : &a;
  for (i = 0; i < n; i++) s += *ps[i];
  return s;
}

/* allocated per iteration, freed at function return — same as alloca itself */
int vla_in_loop(int n)
{
  int i, j, s = 0;
  for (i = 1; i <= n; i++) {
    int row[i];
    for (j = 0; j < i; j++) row[j] = j;
    for (j = 0; j < i; j++) s += row[j];
  }
  return s;
}

/* A CALL IS A LEGAL VLA BOUND, and it was reported as an undeclared
   identifier. FindSym cannot see a C function -- functions live in Procs -- so
   every call in an array dimension reached the not-declared-at-all arm of
   CEvalConstPrimary and refused with `undeclared identifier `strlen''. Found
   attempting busybox at 394 applets: archival/dpkg.c:1442 is
   `char list_name[strlen(package_name) + 25]', and that one line was the whole
   of the TU's refusal.

   THE COMMA ROW IS A SEPARATE SHAPE ON PURPOSE. The dimension site rewinds and
   re-reads the bracket with ParseCExpr, so the fold only has to notice the
   bound is non-constant -- but it must skip the argument list BALANCED to get
   there, because an argument comma errors out inside the fold before any
   rewind can happen. A single-argument call passes either way, which is what
   makes `strlen(s)' alone an inadequate test of the fix. */
static int twice(int a) { return a * 2; }
static int addem(int a, int b) { return a + b; }

int vla_call_bytes(const char *s)   { char b[strlen(s) + 5];  b[0] = 'a'; return (int)sizeof(b); }
int vla_call_dims(int n)            { char b[twice(n) + 1];   b[0] = 'a'; return (int)sizeof(b); }
int vla_call_commas(int n)          { char b[addem(n, 3) + 1]; b[0] = 'a'; return (int)sizeof(b); }

/* a fixed-bound array must still be a real array: sizeof stays constant */
int fixed_bytes(void)
{
  int arr[6];
  arr[0] = 0;
  return (int)sizeof(arr);
}

int main(void)
{
  printf("%d %d\n", vla_sum(5), vla_sum(9));
  printf("%d %d\n", vla_bytes(5), vla_bytes(10));
  printf("%d %d\n", vla_int_bytes(5), vla_int_bytes(10));
  printf("%d\n", vla_pts(3));
  printf("%d\n", vla_ptrs(4));
  printf("%d\n", vla_in_loop(4));
  printf("%d\n", fixed_bytes());
  printf("%d %d %d\n", vla_call_bytes("abcd"), vla_call_dims(3), vla_call_commas(2));
  return 0;
}
