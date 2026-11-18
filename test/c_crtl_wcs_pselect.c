/* crtl's wide-string family (wcschr ... wmemset) and pselect, which st needs:
   wcschr over its word delimiters, pselect in its main loop.
   feature-c-crtl-wcs-family-and-pselect */
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>
#include <sys/select.h>
#include <unistd.h>
#include <time.h>
#include <signal.h>

int main(void)
{
  wchar_t a[32], b[32], *d;
  int fds[2], n;
  fd_set rs;
  struct timespec ts = { 0, 1000000 };
  sigset_t none;

  wcscpy(a, L"hello, wide world");
  printf("%d %d %d\n", (int)(wcschr(a, L'w') - a), (int)(wcsrchr(a, L'o') - a), wcschr(a, L'z') == 0);
  printf("%d %d %d\n", (int)wcsspn(a, L"hel"), (int)wcscspn(a, L" ,"), (int)(wcspbrk(a, L",d") - a));
  printf("%d %d\n", (int)(wcsstr(a, L"wide") - a), wcsstr(a, L"narrow") == 0);
  wcsncpy(b, a, 5); b[5] = 0;
  wcscat(b, L"!"); wcsncat(b, L"???", 2);
  printf("%d %d %d\n", (int)wcslen(b), wcscmp(b, L"hello!??") == 0, wcsncmp(a, b, 5) == 0);
  printf("%d %d\n", wcscmp(L"a", L"b") < 0, wcscmp(L"b", L"a") > 0);
  d = wcsdup(a);
  wmemmove(d + 2, d, 5);
  wmemset(d, L'*', 2);
  printf("%d %d %d\n", wmemcmp(d + 2, L"hello", 5) == 0, d[0] == L'*', (int)(wmemchr(d, L'w', 20) - d));
  printf("%d\n", (int)wcsnlen(a, 4));
  free(d);

  if (pipe(fds) != 0) return 1;
  sigemptyset(&none);
  FD_ZERO(&rs); FD_SET(fds[0], &rs);
  n = pselect(fds[0] + 1, &rs, 0, 0, &ts, &none);
  printf("idle %d\n", n);
  write(fds[1], "x", 1);
  FD_ZERO(&rs); FD_SET(fds[0], &rs);
  n = pselect(fds[0] + 1, &rs, 0, 0, &ts, 0);
  printf("ready %d %d %ld\n", n, FD_ISSET(fds[0], &rs) != 0, (long)ts.tv_nsec);
  return 0;
}
