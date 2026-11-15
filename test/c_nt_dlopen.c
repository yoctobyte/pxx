/* --os=nt: dlopen/dlsym/dlclose (crtl <dlfcn.h> over winabi's LoadLibraryA,
   GetProcAddress, FreeLibrary). test-windows builds nt_dll_pascal_lib.dll next to
   this program first. A pxx DLL's routine comes back as itself (floats and
   eight arguments work); msvcrt's through the generic adapter (integers,
   pointers, all-float arguments, a variadic call with stack arguments). */
#include <stdio.h>
#include <dlfcn.h>
#include <string.h>
int main(void) {
  void *h = dlopen("nt_dll_pascal_lib.dll", RTLD_NOW);
  printf("pxx dll %s\n", h ? "loaded" : dlerror());
  if (h) {
    int (*sum)(int) = (int (*)(int))dlsym(h, "pxx_sum");
    double (*mix)(long long, double, int, double, long long, long long, long long, long long) =
      (double (*)(long long, double, int, double, long long, long long, long long, long long))dlsym(h, "pxx_mix");
    int (*len)(const char *) = (int (*)(const char *))dlsym(h, "pxx_len");
    printf("sum %d\n", sum(100));
    printf("mix %.2f\n", mix(1, 0.5, 2, 0.25, 3, 4, 5, 6));
    printf("len %d\n", len("hello"));
    printf("missing %s\n", dlsym(h, "no_such") ? "found?" : "NULL");
    printf("close %d\n", dlclose(h));
  }
  void *c = dlopen("msvcrt.dll", RTLD_NOW);
  printf("msvcrt %s\n", c ? "loaded" : dlerror());
  if (c) {
    size_t (*sl)(const char *) = (size_t (*)(const char *))dlsym(c, "strlen");
    double (*pw)(double, double) = (double (*)(double, double))dlsym(c, "pow");
    int (*sp)(char *, const char *, ...) = (int (*)(char *, const char *, ...))dlsym(c, "sprintf");
    char buf[128];
    printf("strlen %d\n", (int)sl("abcdefg"));
    printf("pow %.1f\n", pw(2.0, 10.0));
    sp(buf, "%d %d %d %d %d %d %d %d %s", 1, 2, 3, 4, 5, 6, 7, 8, "nine");
    printf("sprintf [%s]\n", buf);
  }
  printf("bad %s\n", dlopen("no_such_library.dll", RTLD_NOW) ? "loaded?" : "NULL");
  return 0;
}
