/* %X is the same conversion as %x in scanf (C11 7.21.6.2). crtl knew only
   %x, so every %X failed: toybox cpio reads its newc header with
   sscanf(hex, "%7X%n", ...) and stopped at "bad hex" (bug-c-toybox-test-
   suite-failures). Both engines are covered: sscanf (strings) and fscanf
   (streams) parse the format separately. */
#include <stdio.h>

static void one(const char *s, const char *f)
{
  unsigned v = 12345;
  int n = -7;
  int r = sscanf(s, f, &v, &n);
  printf("%-14s %-8s r=%d v=%u n=%d\n", s, f, r, v, n);
}

static void stream(void)
{
  unsigned v = 0, w = 0;
  int n = -1;
  FILE *f = tmpfile();
  fputs("1A4 0XfF zz", f);
  rewind(f);
  int r = fscanf(f, "%X %X%n", &v, &w, &n);
  printf("fscanf r=%d v=%u w=%u n=%d\n", r, v, w, n);
  fclose(f);
}

int main(void)
{
  one("1A4000000xx", "%3X%n");
  one("1A4000000xx", "%3x%n");
  one("000001A4", "%8X%n");
  one("1A4", "%X%n");
  one("1a4", "%X%n");
  one("ffffffff1", "%8X%n");
  one("0x1A4", "%X%n");
  one("12345678", "%4u%n");
  one("1A", "%1X%n");
  stream();
  return 0;
}
