/* The host side of test/test_os_objlink.pas: see that file. */
#include <stdio.h>
int pxx_sum(int); int pxx_flag(void); int pxx_greet(int); int pxx_catch(int);
int main(void) {
  setvbuf(stdout, 0, _IONBF, 0);
  printf("sum=%d\n", pxx_sum(10));
  printf("flag=%d\n", pxx_flag());
  printf("len=%d\n", pxx_greet(7));
  printf("caught len=%d\n", pxx_catch(3));
  printf("none=%d\n", pxx_catch(0));
  return 0;
}
