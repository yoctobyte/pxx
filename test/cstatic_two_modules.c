/* A file-scope `static` in two different crtl MODULES is legal C, and must not
   be reported as a duplicate definition.
 
   The preprocessor inlines every #include into ONE buffer and crtl's modules
   are pulled into that same buffer, so by parse time lib/crtl/src/fcntl.c and
   lib/crtl/src/unistd.c are one translation unit as far as pxx is concerned.
   C disagrees: file-scope `static` has INTERNAL linkage, so the same name in
   two modules is two distinct functions and gcc compiles it. Both of those
   define `static sysret`, so any program reaching open() and dup() warned on
   correct code -- as did six `__pxx_va_*_impl` statics from stdarg.h, which the
   crtl prototype pull expands a second time in a separately-preprocessed block.
 
   Measured earlier (see the ticket): each caller already BOUND its own module's
   body in both pull orders, so this was a false warning and never a miscompile.
   bug-c-static-functions-in-different-crtl-modules-collide
 
   The matching TRUE positive -- two same-named statics in ONE real .c -- is
   test/cstatic_same_module_dup.c, which must still warn. Both halves matter:
   suppressing statics wholesale would trade this false positive for that lost
   true positive. */

#include <stdarg.h>      /* six file-scope statics, re-expanded by the pull */
#include <fcntl.h>       /* static sysret */
#include <unistd.h>      /* static sysret, again */

extern int printf(const char *, ...);   /* a hand prototype => crtl pull */

static void vp(int n, ...) {
  va_list ap;
  int a;
  va_start(ap, n);
  a = va_arg(ap, int);
  va_end(ap);
  printf("va=%d\n", a);
}

int main(void) {
  int fd;
  int dupfd;

  vp(1, 42);

  /* reaches fcntl.c's sysret */
  fd = open("/dev/null", O_RDONLY);
  printf("open=%d\n", fd >= 0);

  /* ...and unistd.c's, the other definition of the same name */
  dupfd = dup(fd);
  printf("dup=%d\n", dupfd >= 0);
  printf("close=%d\n", close(dupfd) == 0);
  printf("close2=%d\n", close(fd) == 0);
  return 0;
}
