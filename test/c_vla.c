/* C variable-length arrays, lowered through alloca (feature-c-vla-via-alloca).
   The loop shape is the one that used to stop after two iterations: a VLA sized
   at a silent ZERO sat on top of the next stack slot, so writing through it
   clobbered the loop's own counter (bug-cfront-vla-stack-corruption).
   Every number here is gcc's answer on the same source. */
#include <stdio.h>

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
  return 0;
}
