#include <stdarg.h>

int plus_one(int x) {
  return x + 1;
}

int take_callback(int op, ...) {
  va_list ap;
  va_start(ap, op);
  if (op) {
    typedef int (*LOGFUNC_t)(int);
    LOGFUNC_t fn = va_arg(ap, LOGFUNC_t);
    int r = fn(41);
    va_end(ap);
    return r;
  }
  va_end(ap);
  return 1;
}

int main(void) {
  return take_callback(1, plus_one);
}
