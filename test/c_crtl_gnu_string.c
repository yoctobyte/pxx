/* crtl's GNU string/stdio extensions, against glibc. Every expected line here
   was taken from a glibc-built binary of this same file.

   strverscmp is the row set worth reading: its rule is subtler than "compare
   the two integers". A digit run with LEADING ZEROS is a FRACTIONAL part in
   glibc and sorts BEFORE one without, so "file.01" < "file.1" even though 1
   equals 1 -- and "x001" < "x01" for the same reason. An implementation that
   only compares magnitudes passes the file9/file10 rows and fails these.

   Only the SIGN is asserted: the magnitude of a strcmp-family return is not
   specified and glibc's is not a contract. feature-c-corpus-busybox-applet */
#define _GNU_SOURCE 1        /* glibc gates these; crtl declares them unconditionally */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>

static int via_v(char **out, const char *fmt, ...)
{ va_list ap; int r; va_start(ap, fmt); r = vasprintf(out, fmt, ap); va_end(ap); return r; }

int main(void)
{
  char b[32];
  /* mempcpy: returns the end */
  { char *e = (char *)mempcpy(b, "abc", 3); *e = 0;
    printf("mempcpy: [%s] off=%d\n", b, (int)(e - b)); }
  /* stpncpy: pointer to the NUL, or dest+n when it did not fit; pads */
  { memset(b, 'Z', sizeof(b));
    char *e = stpncpy(b, "ab", 6);
    printf("stpncpy fit: off=%d pad=%d%d%d\n", (int)(e - b), b[2], b[3], b[5]); }
  { memset(b, 'Z', sizeof(b));
    char *e = stpncpy(b, "abcdefgh", 4);
    printf("stpncpy trunc: off=%d c3=%c\n", (int)(e - b), b[3]); }
  /* strchrnul */
  printf("strchrnul hit: %d\n", (int)(strchrnul("hello", 'l') - "hello"));
  printf("strchrnul miss: %d\n", (int)(strchrnul("hello", 'z') - "hello"));
  printf("strchrnul nul: %d\n", (int)(strchrnul("hello", 0) - "hello"));
  /* rawmemchr */
  printf("rawmemchr: %d\n", (int)((char *)rawmemchr("hello", 'l') - "hello"));
  /* memmem */
  printf("memmem hit: %d\n", (int)((char *)memmem("abcdef", 6, "cd", 2) - "abcdef"));
  printf("memmem miss: %d\n", memmem("abcdef", 6, "xy", 2) == 0);
  printf("memmem empty: %d\n", (int)((char *)memmem("abcdef", 6, "", 0) - "abcdef"));
  printf("memmem toolong: %d\n", memmem("ab", 2, "abc", 3) == 0);
  /* strverscmp — sign only; glibc's magnitudes are not specified */
#define SGN(x) ((x) < 0 ? -1 : ((x) > 0 ? 1 : 0))
  printf("vs 9v10: %d\n",    SGN(strverscmp("file9", "file10")));
  printf("vs 10v9: %d\n",    SGN(strverscmp("file10", "file9")));
  printf("vs eq: %d\n",      SGN(strverscmp("file10", "file10")));
  printf("vs .01v.1: %d\n",  SGN(strverscmp("file.01", "file.1")));
  printf("vs 1v01: %d\n",    SGN(strverscmp("file.1", "file.01")));
  printf("vs plain: %d\n",   SGN(strverscmp("abc", "abd")));
  printf("vs pfx: %d\n",     SGN(strverscmp("abc", "abcd")));
  printf("vs a1bv a1a: %d\n",SGN(strverscmp("a1b", "a1a")));
  printf("vs 001v01: %d\n",  SGN(strverscmp("x001", "x01")));

  /* asprintf/vasprintf: exact-fit allocation, caller owns it. Row 3 is longer
     than any plausible stack buffer, so it proves the allocation is sized from
     the measuring pass rather than capped. Row 4 goes through a va_list: the
     measuring pass CONSUMES the ap, so the formatting pass needs a va_copy —
     without it every ABI with an array va_list reads garbage. */
  { char *p; int n;
    n = asprintf(&p, "%s-%d-%05.2f-%x", "abc", -42, 3.5, 255);
    printf("asprintf 1: n=%d len=%d [%s]\n", n, (int)strlen(p), p); free(p);
    n = asprintf(&p, "");
    printf("asprintf 2: n=%d len=%d\n", n, (int)strlen(p)); free(p);
    { char big[600]; memset(big, 'z', 599); big[599] = 0;
      n = asprintf(&p, "%s|%s", big, big);
      printf("asprintf 3: n=%d len=%d tailok=%d\n", n, (int)strlen(p), p[n-1] == 'z');
      free(p); }
    n = via_v(&p, "%d %s %d %s %d", 1, "two", 3, "four", 5);
    printf("vasprintf 4: n=%d [%s]\n", n, p); free(p); }
  return 0;
}
