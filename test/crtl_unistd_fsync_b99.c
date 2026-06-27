/* crtl unistd.h declares sqlite's needed POSIX imports. The local function
   pointer initializers force the C frontend to resolve the header prototypes
   without making the test depend on host filesystem syscall behavior. Exit 42. */
#include <unistd.h>

int main(void) {
  if (0) return fsync(-1);
  return sysconf(_SC_PAGESIZE) > 0 && (_SC_PAGE_SIZE == _SC_PAGESIZE) ? 42 : 1;
}
