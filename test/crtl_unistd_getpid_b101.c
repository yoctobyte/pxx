/* crtl unistd.h declares getpid as a libc import. sqlite's unix VFS uses it
   after the preprocessor directive-join wall. Exit 42. */
#include <unistd.h>

int main(void) {
  return getpid() > 0 ? 42 : 1;
}
