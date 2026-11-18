/* crtl functions the X libraries need (Path B): multibyte in the C locale,
   isascii, strtof, IOV_MAX, the IN6_IS_ADDR tests, random_r (glibc's
   sequence for a seed), arc4random. Output must match gcc + glibc. */
#define _GNU_SOURCE 1
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <limits.h>
#include <string.h>
#include <netinet/in.h>

static void in6(const char *name, const unsigned char *b)
{
  struct in6_addr a;
  memcpy(&a, b, 16);
  printf("%s u%d l%d m%d c%d mc%d ll%d sl%d\n", name,
         IN6_IS_ADDR_UNSPECIFIED(&a) != 0, IN6_IS_ADDR_LOOPBACK(&a) != 0,
         IN6_IS_ADDR_V4MAPPED(&a) != 0, IN6_IS_ADDR_V4COMPAT(&a) != 0,
         IN6_IS_ADDR_MULTICAST(&a) != 0, IN6_IS_ADDR_LINKLOCAL(&a) != 0,
         IN6_IS_ADDR_SITELOCAL(&a) != 0);
}

static void rnd(unsigned int seed, size_t len)
{
  static char st[300];
  struct random_data rd;
  int r, i, rc;
  memset(&rd, 0, sizeof rd);
  memset(st, 0, sizeof st);
  rc = initstate_r(seed, st, len, &rd);
  printf("seed %u len %d rc %d:", seed, (int)len, rc);
  for (i = 0; i < 4; i++) { random_r(&rd, &r); printf(" %d", r); }
  srandom_r(seed + 1, &rd);
  random_r(&rd, &r);
  printf(" | %d\n", r);
}

int main(void)
{
  wchar_t w[8], wc;
  char m[8];
  unsigned char z[16] = {0}, lo[16] = {0}, v4m[16] = {0}, v4c[16] = {0}, mc[16] = {0}, ll[16] = {0}, sl[16] = {0};
  unsigned char buf[300];
  size_t n;
  int i;

  i = mbtowc(&wc, "A", 1);
  printf("mbtowc %d %d %d mblen %d %d\n", i, (int)wc, mbtowc(0, "\xe9", 1),
         mblen("", 1), mblen(0, 0));
  n = mbstowcs(w, "hey", 8);
  printf("mbstowcs %d %d %d", (int)n, (int)w[0], (int)w[3]);
  printf(" len %d bad %d\n", (int)mbstowcs(0, "abcdef", 0), (int)mbstowcs(w, "a\xe9", 8));
  i = wctomb(m, L'x');
  printf("wctomb %d %c %d\n", i, m[0], wctomb(m + 1, 0xe9));
  w[0] = 'o'; w[1] = 'k'; w[2] = 0;
  n = wcstombs(m, w, 8);
  printf("wcstombs %d %s", (int)n, m);
  printf(" trunc %d\n", (int)wcstombs(m, w, 1));
  printf("isascii %d %d %d toascii %d\n", isascii('a') != 0, isascii(200) != 0, isascii(-1) != 0, toascii(0xc1));
  printf("strtof %.7g %.7g IOV_MAX %d\n", (double)strtof("3.14159265", 0), (double)strtof("1e-3", 0), IOV_MAX);

  lo[15] = 1;
  v4m[10] = 0xff; v4m[11] = 0xff; v4m[12] = 10; v4m[15] = 1;
  v4c[12] = 10; v4c[15] = 1;
  mc[0] = 0xff; mc[1] = 2;
  ll[0] = 0xfe; ll[1] = 0x80;
  sl[0] = 0xfe; sl[1] = 0xc0;
  in6("zero", z); in6("lo", lo); in6("v4m", v4m); in6("v4c", v4c);
  in6("mc", mc); in6("ll", ll); in6("sl", sl);

  rnd(42, 128); rnd(1, 8); rnd(0, 32); rnd(7, 64); rnd(3000000000u, 256);

  memset(buf, 0, sizeof buf);
  arc4random_buf(buf, sizeof buf);
  for (n = 0, i = 0; i < 300; i++) n += buf[i] != 0;
  printf("arc4random %d %d\n", n > 250, arc4random_uniform(10) < 10);
  return 0;
}
