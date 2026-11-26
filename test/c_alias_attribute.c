/* __attribute__((alias("target"))): another name for a function or object
   defined in this file -- a prototype, a __typeof'd declaration (dhcpcd's
   compat/setproctitle.c, Nodisx), weak, and data. It was dropped, and the
   name stayed an undefined import. Built with --emit-obj and linked against
   test/c_alias_attribute_main.c, against gcc.
   bug-c-the-alias-attribute-was-ignored */
#include <stdio.h>
#include <stdarg.h>
int vsum(int n, ...);
static int impl_vsum(int n, ...)   /* static, as dhcpcd's setproctitle_impl */
{
  va_list ap; int s = 0;
  va_start(ap, n);
  while (n-- > 0) s += va_arg(ap, int);
  va_end(ap);
  return s;
}
extern __typeof(impl_vsum) vsum __attribute__((__alias__("impl_vsum")));
int impl_add(int a, int b) { return a + b; }
int add(int a, int b) __attribute__((alias("impl_add")));
int impl_weak(void) { return 41; }
int weakname(void) __attribute__((weak, alias("impl_weak")));
int counter_storage = 5;
extern int counter __attribute__((alias("counter_storage")));
