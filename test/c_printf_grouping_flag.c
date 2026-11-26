/* printf's POSIX `'` flag (group by the locale's thousands_sep) in the C
   locale: accepted, consumes its argument, and groups by nothing -- so the
   arguments after it stay in place. It used to print the directive
   literally and shift every later argument (xz-utils probes `%'u`; Nodisx).
   Expected = glibc's in the C locale. */
#include <stdio.h>
#include <locale.h>
int main(void)
{
  char buf[64];
  setlocale(LC_ALL, "C");
  printf("[%'d] [%'u] [%'ld] [%'.1f] [%s]\n", 1234567, 7101u, -9876543210L, 7101.25, "after");
  printf("[%'10d] [%-'8u] [%'+d] [%'08d]\n", 12345, 678u, 4242, 99);
  snprintf(buf, sizeof buf, "%'u", 1u);
  printf("probe=[%s] %s\n", buf, buf[0] == '1' ? "WORKS" : "BROKEN");
  return 0;
}
