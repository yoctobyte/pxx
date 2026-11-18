#include <stdio.h>
int ctor_count(void);
int ctor_at(int i);
int main(void)
{
  int i;
  printf("ctors %d:", ctor_count());
  for (i = 0; i < ctor_count(); i++) printf(" %d", ctor_at(i));
  printf("\n");
  return 0;
}
