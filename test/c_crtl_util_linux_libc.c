/* SPDX-License-Identifier: Zlib */
/* The libc calls util-linux (sfdisk, fdisk, blkid) needed that crtl did not
   have, run against GLIBC'S ANSWERS: no expected file, the gcc build of this
   same source is the reference. fmemopen in every mode, with the edges a
   caller meets (a write past the size, a seek past it, a `b' mode, size 0,
   reading a stream that ends before the caller's buffer does); rpmatch;
   strtod_l in the C locale; the <stdio_ext.h> answers right after an fflush;
   sendfile with and without an offset; getttynam with no /etc/ttys. */
#define _GNU_SOURCE 1
#include <stdio.h>
#include <stdio_ext.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <locale.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/sendfile.h>
#include <ttyent.h>

static void show(const char *what, const char *buf, size_t n)
{
  size_t i;
  printf("%s [", what);
  for (i = 0; i < n; i++) {
    if (buf[i] == 0) printf("\\0");
    else putchar(buf[i]);
  }
  printf("]\n");
}

int main(void)
{
  char buf[16], line[64], big[8192];
  FILE *f;
  int c, n;
  long pos;
  char *lp = 0;
  size_t lcap = 0;
  ssize_t ll;

  /* "r": read it all, then end of file */
  f = fmemopen("one\ntwo\nthree", 13, "r");
  while ((ll = getline(&lp, &lcap, f)) > 0) printf("r line %ld: %s%s", (long)ll, lp, lp[ll - 1] == '\n' ? "" : "\n");
  printf("r feof %d ferror %d ftell %ld\n", feof(f) != 0, ferror(f) != 0, ftell(f));
  rewind(f);
  c = fgetc(f); ungetc(c, f);
  pos = ftell(f);
  c = fgetc(f);
  printf("r after rewind+ungetc: ftell %ld fgetc %c\n", pos, c);
  n = fseek(f, -2, SEEK_END);
  c = fgetc(f);
  printf("r fseek END-2 %d -> %c\n", n, c);
  errno = 0;
  n = fseek(f, 14, SEEK_SET);
  printf("r fseek past the size %d errno %s\n", n, errno == EINVAL ? "EINVAL" : "other");
  fseek(f, 0, SEEK_SET);
  printf("r fread big %ld\n", (long)fread(big, 1, sizeof big, f));
  fclose(f);

  /* "w": starts empty, a NUL follows the contents, the size is the limit */
  memset(buf, 'x', sizeof buf);
  f = fmemopen(buf, 8, "w");
  n = fprintf(f, "ab%d", 12);
  fflush(f);
  show("w after fprintf", buf, 8);
  printf("w fprintf %d ftell %ld\n", n, ftell(f));
  fputs("cdefgh", f);
  fflush(f);
  show("w after the overflow", buf, 9);
  printf("w ferror %d\n", ferror(f) != 0);
  fclose(f);

  /* "a": from the first NUL */
  strcpy(buf, "abc");
  f = fmemopen(buf, 10, "a");
  pos = ftell(f);
  fputs("de", f);
  fflush(f);
  printf("a start %ld now %ld\n", pos, ftell(f));
  show("a", buf, 6);
  fclose(f);

  /* "r+": read some, write over the middle */
  strcpy(buf, "0123456789");
  f = fmemopen(buf, 10, "r+");
  c = fgetc(f);
  n = fgetc(f);
  printf("r+ fgetc %c %c\n", c, n);
  fseek(f, 0, SEEK_CUR);
  fputs("AB", f);
  fflush(f);
  show("r+", buf, 11);
  fclose(f);

  /* "wb": glibc gives the `b' no meaning */
  memset(buf, 'x', sizeof buf);
  f = fmemopen(buf, 8, "wb");
  fputs("hi", f);
  fflush(f);
  show("wb", buf, 4);
  fclose(f);

  /* a NULL buffer: crtl's own, freed by fclose */
  f = fmemopen(NULL, 32, "w+");
  fputs("scratch", f);
  rewind(f);
  printf("w+ NULL buf reads back: %s\n", fgets(line, sizeof line, f));
  fclose(f);
  f = fmemopen(buf, 0, "r");
  printf("fmemopen size 0: %s", f ? "stream" : "NULL");
  if (f) { printf(", fgetc %d", fgetc(f)); fclose(f); }
  f = fmemopen(buf, 4, "q");
  printf(", mode q: %s\n", f ? "stream" : "NULL");

  /* rpmatch */
  printf("rpmatch y %d Yes %d n %d No %d x %d empty %d\n", rpmatch("y"), rpmatch("Yes"),
         rpmatch("n"), rpmatch("No"), rpmatch("x"), rpmatch(""));

  /* strtod_l in C */
  {
    locale_t cl = newlocale(LC_ALL_MASK, "C", (locale_t)0);
    char *end;
    double d = strtod_l("3.25e2xyz", &end, cl);
    printf("strtod_l %.2f rest %s\n", d, end);
    freelocale(cl);
  }

  /* <stdio_ext.h> */
  fputs("", stdout);
  fflush(stdout);
  printf("__fpending after fflush %ld\n", (long)(fflush(stdout), __fpending(stdout)));
  {
    int q1 = __fsetlocking(stdout, FSETLOCKING_QUERY);
    int s1 = __fsetlocking(stdout, FSETLOCKING_BYCALLER);
    int q2 = __fsetlocking(stdout, FSETLOCKING_QUERY);
    int s2 = __fsetlocking(stdout, FSETLOCKING_INTERNAL);
    int q3 = __fsetlocking(stdout, FSETLOCKING_QUERY);
    printf("__fsetlocking query %d set %d query %d set %d query %d\n", q1, s1, q2, s2, q3);
  }
  _flushlbf();

  /* sendfile: file to file, with an offset and without */
  {
    char src[] = "/tmp/pxx-sendfile-srcXXXXXX", dst[] = "/tmp/pxx-sendfile-dstXXXXXX";
    int in = mkstemp(src), out = mkstemp(dst);
    off_t off = 4;
    ssize_t r1, r2;
    write(in, "0123456789", 10);
    r1 = sendfile(out, in, &off, 3);
    lseek(in, 1, SEEK_SET);
    r2 = sendfile(out, in, NULL, 2);
    printf("sendfile %ld off now %ld, %ld from the fd position\n", (long)r1, (long)off, (long)r2);
    lseek(out, 0, SEEK_SET);
    n = (int)read(out, line, sizeof line);
    show("sendfile copied", line, (size_t)n);
    close(in); close(out); unlink(src); unlink(dst);
  }

  /* no /etc/ttys */
  printf("getttynam tty1: %s\n", getttynam("tty1") ? "entry" : "NULL");
  n = setttyent();
  c = getttyent() != 0;
  printf("setttyent %d getttyent %s", n, c ? "entry" : "NULL");
  printf(" endttyent %d\n", endttyent());
  free(lp);
  return 0;
}
