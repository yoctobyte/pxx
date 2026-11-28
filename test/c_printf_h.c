/* SPDX-License-Identifier: Zlib */
/* <printf.h>: parse_printf_format's count and argument types on many
   templates, against gcc + glibc. Row c_prfh26.
   feature-crtl-printf-h-parse-printf-format */
#include <stdio.h>
#include <printf.h>

static const char *fmts[] = {
  "", "plain", "%%", "%d", "%i %u %x %X %o", "%hd %hhd %ld %lld %qd %Lu",
  "%jd %zu %zd %td %Zu", "%c %lc %C", "%s %ls %S", "%p", "%n %hn %hhn %ln %lln",
  "%f %e %g %a %Lf %LE %lf", "%*d", "%.*s", "%*.*f", "%-08.3f|%+d|% d|%#x|%'d",
  "%2$s %1$d", "%3$*1$.*2$d", "%m %d", "%5$d", "a%sb%dc%%d%cd%p%f%ld",
  "%hhu %hhx %hhc", "%lln %jn %zn", "%Lf %qf %llf %Ld %lld",
};

int main(void)
{
  unsigned i;
  for (i = 0; i < sizeof fmts / sizeof fmts[0]; i++) {
    int t[16];
    size_t k, j;
    for (j = 0; j < 16; j++) t[j] = -1;
    k = parse_printf_format(fmts[i], 16, t);
    printf("%-22s %zu:", fmts[i], k);
    for (j = 0; j < k && j < 16; j++) printf(" %#x", t[j]);
    printf("\n");
  }
  {
    int t[2] = { -1, -1 };
    printf("short n=2 %zu %#x %#x\n", parse_printf_format("%d %s %f %p", 2, t), t[0], t[1]);
  }
  return 0;
}
