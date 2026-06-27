#include <sys/types.h>

ssize_t f(void) {
  return 7;
}

int main(void) {
  return f() == 7 ? 42 : 1;
}
