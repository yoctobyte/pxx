/* the host side of c_rename_globals_kernel.c: not renamed */
#include <stdio.h>
extern int rumpns_kernel_entry(int);
extern int rumpns_shared_counter;
extern int __keep_me(void);
int rumpns_memcpy_user(int x) { return x + 10; }
int rumpuser_thing(int x) { return x * 2; }
int main(void) {
  rumpns_shared_counter = 5;
  /* (1+10+5) + 2 + 100 = 118 */
  printf("%d %d\n", rumpns_kernel_entry(1), __keep_me());
  return 0;
}
