/* <dlfcn.h> over the PAL loader. Default (libc-free) build: dlopen is NULL,
   dlerror has a message and clears on the second call. With -dPXX_DYNLIB_LIBC:
   the real loader, output equal to gcc -ldl (test/c_crtl_dlfcn_libc.expected).
   bug-c-sqlite-with-threadsafe-stops-at-a-stray-BEGIN_DECLS */
#include <stdio.h>
#include <dlfcn.h>
int main(void) {
  void *h = dlopen("libm.so.6", RTLD_NOW | RTLD_GLOBAL);
  if (!h) {
    char *e = dlerror();
    printf("no handle: %s\n", e ? "message" : "NULL-message");
    printf("second dlerror: %s\n", dlerror() ? "set" : "cleared");
    return 0;
  }
  double (*c)(double) = (double (*)(double))dlsym(h, "cos");
  printf("cos(0)=%g\n", c ? c(0.0) : -1.0);
  printf("missing=%s ", dlsym(h, "no_such_symbol_xyz") ? "found" : "NULL");
  printf("err=%s\n", dlerror() ? "set" : "none");
  printf("close=%d\n", dlclose(h));
  return 0;
}
