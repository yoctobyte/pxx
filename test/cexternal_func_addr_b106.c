/* A bare imported C function name decays to a function-pointer value. sqlite's
   unixDlSym casts libc dlsym to a function-pointer type before calling it.
   Exit 42. */
typedef int (*puts_fn)(const char *);

int puts(const char *s);

int main(void) {
  puts_fn f;
  f = (puts_fn)puts;
  return f == 0 ? 1 : 42;
}
