/* Half B -- see c_obj_fnptr_a.c. Rebinds the pointer A defined, then calls
   back into A: the write must be visible through A's own reference, which is
   the two-sided half a symbol alone does not give. */
#include <stdio.h>

typedef int (*fp_t)(int);

extern fp_t Handler;
int call_handler(int);

static int inc(int x) { return x + 1; }

int main(void)
{
  printf("%d ", call_handler(10));
  Handler = inc;
  printf("%d\n", call_handler(10));
  return 0;
}
