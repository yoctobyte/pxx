/* iconv: the DOS code pages FAT names use (CP437, CP850), every byte both
   ways, against glibc's converters. Expected output = gcc + glibc's. */
#include <errno.h>
#include <iconv.h>
#include <stdio.h>
#include <string.h>

static void one(const char *cs)
{
  iconv_t d = iconv_open("UTF-8", cs), e = iconv_open(cs, "UTF-8");
  int b, bad = 0;
  if (d == (iconv_t)-1 || e == (iconv_t)-1) { printf("%s: iconv_open failed\n", cs); return; }
  printf("%s:", cs);
  for (b = 0; b < 256; b++) {
    char in[1], u[8], back[4];
    char *ip = in, *op = u, *up, *bp = back;
    size_t il = 1, ol = sizeof u, ul, bl = sizeof back;
    int i;
    in[0] = (char)b;
    if (iconv(d, &ip, &il, &op, &ol) == (size_t)-1) { printf(" [%02x:err]", b); bad++; continue; }
    if (b >= 128 && b % 16 == 0) printf("\n ");
    if (b >= 128) {
      putchar(' ');
      for (i = 0; u + i < op; i++) printf("%02x", (unsigned char)u[i]);
    }
    up = u; ul = (size_t)(op - u);
    if (iconv(e, &up, &ul, &bp, &bl) == (size_t)-1 || bp - back != 1 || (unsigned char)back[0] != b)
      { printf(" [%02x:roundtrip]", b); bad++; }
  }
  printf("\n%s: %d bad\n", cs, bad);
  { /* a character neither set has: EILSEQ */
    char u[] = "\xe2\x82\xac", o[4], *ip = u, *op = o;
    size_t il = 3, ol = sizeof o;
    size_t r = iconv(e, &ip, &il, &op, &ol);
    printf("%s euro: %s\n", cs, r == (size_t)-1 && errno == EILSEQ ? "EILSEQ" : "converted");
  }
  iconv_close(d);
  iconv_close(e);
}

int main(void)
{
  const char *alias[] = { "IBM437", "437", "IBM850", "850", "cp850", 0 };
  int i;
  one("CP437");
  one("CP850");
  for (i = 0; alias[i]; i++) {
    iconv_t c = iconv_open(alias[i], "UTF-8");
    printf("%s: %s\n", alias[i], c == (iconv_t)-1 ? "unknown" : "ok");
    if (c != (iconv_t)-1) iconv_close(c);
  }
  return 0;
}
