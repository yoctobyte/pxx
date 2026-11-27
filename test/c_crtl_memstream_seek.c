/* SPDX-License-Identifier: Zlib */
/* open_memstream with a position, against glibc: fseek/rewind/ftell on it,
   writes over earlier bytes after a seek back, a seek past the end (zeros),
   SEEK_END (glibc counts it from the current position), a negative position
   (EINVAL), the size after fflush (the position) and after fclose (cut there
   and NUL-terminated), fileno (-1). Then dhcpcd's pattern (script.c): one
   stream rewound and refilled with NUL-separated "NAME=value" strings for
   every hook run; crtl's appended instead and ftell failed with EBADF, so
   every run's environment was refused. */
#define _GNU_SOURCE 1
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdarg.h>

static char *buf; static size_t len;
static void show(const char *what, FILE *fp)
{
  size_t i;
  long t = ftell(fp);
  printf("%-22s len=%zu tell=%ld buf=", what, len, t);
  for (i = 0; i < len + 1; i++) putchar(buf[i] ? buf[i] : '|');
  printf("\n");
}

static int efprintf(FILE *fp, const char *fmt, ...)
{
  va_list a; int r;
  va_start(a, fmt); r = vfprintf(fp, fmt, a); va_end(a);
  if (r == -1) return -1;
  if (fputc('\0', fp) == EOF) return -1;
  return r + 1;
}

int main(void)
{
  FILE *fp = open_memstream(&buf, &len);
  int r, round, e;
  fputs("hello world", fp); fflush(fp); show("write 11", fp);
  r = fseek(fp, 2, SEEK_SET); printf("fseek 2: %d\n", r); fflush(fp); show("seek 2, flush", fp);
  fputs("XY", fp); fflush(fp); show("write XY at 2", fp);
  r = fseek(fp, 0, SEEK_END); printf("fseek end: %d\n", r); fflush(fp); show("seek end", fp);
  r = fseek(fp, -3, SEEK_END); printf("fseek end-3: %d\n", r); fflush(fp); show("seek end-3", fp);
  r = fseek(fp, 20, SEEK_SET); printf("fseek 20: %d\n", r); fflush(fp); show("seek 20", fp);
  fputs("Z", fp); fflush(fp); show("write Z", fp);
  errno = 0; r = fseek(fp, -1, SEEK_SET); e = errno; printf("fseek -1: %d errno %d\n", r, e); show("after -1", fp);
  r = fseek(fp, 3, SEEK_CUR); printf("fseek cur+3: %d\n", r); fflush(fp); show("cur+3", fp);
  r = fseeko(fp, 5, SEEK_SET); printf("fseeko 5: %d ftello %ld\n", r, (long)ftello(fp));
  rewind(fp); fflush(fp); show("rewind", fp);
  fprintf(fp, "%d", 12345); fflush(fp); show("printf 12345", fp);
  fputc('\0', fp); fflush(fp); show("putc NUL", fp);
  errno = 0; r = fileno(fp); e = errno; printf("fileno %d errno %d\n", r, e);
  fclose(fp);
  printf("closed len=%zu buf=%s\n", len, buf);
  free(buf);

  buf = 0; len = 0;
  fp = open_memstream(&buf, &len);
  for (round = 0; round < 3; round++) {
    long at;
    if (round) rewind(fp);
    efprintf(fp, "PATH=%s", "/bin");
    efprintf(fp, "pid=%d", 42 + round);
    if (round == 1) efprintf(fp, "reason=%s", "BOUND");
    at = ftell(fp);
    fflush(fp);
    printf("round %d ftell %ld len %zu:", round, at, len);
    { size_t i; for (i = 0; i < len; i++) putchar(buf[i] ? buf[i] : '|'); }
    printf("\n");
  }
  fclose(fp);
  free(buf);
  return 0;
}
