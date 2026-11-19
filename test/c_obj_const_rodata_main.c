#include <stdio.h>
int ro_sum(void);
long ro_aladdr(void);
int main(void) {
  int x = ro_sum();
  int y = ro_sum();
  printf("%d %d %ld\n", x, y, ro_aladdr());
  return 0;
}
