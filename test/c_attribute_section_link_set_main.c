#include <stdio.h>
int items_count(void);
int items_sum(void);
int ls_a_unrelated(void);
int main(void)
{
  printf("count %d sum %d other %d\n", items_count(), items_sum(), ls_a_unrelated());
  return 0;
}
