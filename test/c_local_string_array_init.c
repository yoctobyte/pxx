/* A block-scope array initialised from a STRING literal.
 *
 * The same construct at file scope was never capped; the block-scope path
 * expanded it into per-character element nodes parked in a 256-entry stack
 * array and refused past that with "local string-initialised array exceeds 256
 * bytes". busybox's networking/httpd.c stopped a 400-translation-unit build on
 * a 331-byte `static const char suffixTable[]' -- one construct, two paths, and
 * only the local one had a limit.
 *
 * Row 1 is the busybox shape and the only row that needed the fix. Every other
 * row is a control: they all passed before it, and a change that removes a cap
 * by removing the element expansion would break them.
 */
#include <stdio.h>
#include <string.h>
#include <wchar.h>

static int walk(const char *p, int n)
{
  int c = 0;
  const char *e = p + n;
  for (; p < e && *p; p += strlen(p) + 1) c++;
  return c;
}

static int suffixes(void)
{
  /* 331 bytes: past the old cap, and NUL-separated so a truncated copy counts
     fewer entries rather than crashing. */
  static const char suffixTable[] =
    ".txt.h.c.cc.cpp\0" "text/plain\0"
    ".htm.html\0" "text/html\0"
    ".jpg.jpeg\0" "image/jpeg\0"
    ".gif\0"      "image/gif\0"
    ".png\0"      "image/png\0"
    ".svg\0"      "image/svg+xml\0"
    ".css\0"      "text/css\0"
    ".js\0"       "application/javascript\0"
    ".wav\0"      "audio/wav\0"
    ".avi\0"      "video/x-msvideo\0"
    ".qt.mov\0"   "video/quicktime\0"
    ".mpe.mpeg\0" "video/mpeg\0"
    ".mid.midi\0" "audio/midi\0"
    ".mp3\0"      "audio/mpeg\0"
  ;
  printf("1 %d %d %d\n", (int)sizeof(suffixTable), walk(suffixTable, (int)sizeof(suffixTable)),
         (int)suffixTable[(int)sizeof(suffixTable) - 1]);
  return 0;
}

/* A NON-static local is a fresh copy every call: writing through it must not
   be visible to the next call. A shared static would pass row 2 and fail row 3,
   which is the one way an "optimisation" of this path goes wrong. */
static int fresh(void)
{
  char buf[] = "abcdef";
  int first = buf[0];
  buf[0] = 'Z';
  return first;
}

int main(void)
{
  static const char st[] = "hello";
  char loc[] = "world";
  static const char sized[4] = "abcdef";     /* truncates, no NUL (C99 6.7.8p14) */
  char adj[] = "one" "two" "three";
  static const wchar_t wid[] = L"éx";

  suffixes();
  printf("2 %d %d %d %d\n", (int)sizeof(st), (int)st[0], (int)st[4], (int)st[5]);
  printf("3 %d %d\n", fresh(), fresh());
  printf("4 %d %d %d\n", (int)sizeof(loc), (int)loc[0], (int)loc[5]);
  printf("5 %d %d %d %d\n", (int)sizeof(sized), (int)sized[0], (int)sized[3], (int)sized[2]);
  printf("6 %d %d %d\n", (int)sizeof(adj), (int)strlen(adj), (int)adj[3]);
  printf("7 %d %d %d\n", (int)(sizeof(wid) / sizeof(wid[0])), (int)wid[0], (int)wid[1]);
  return 0;
}
