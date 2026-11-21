/* Escapes in wide string and character literals, against gcc
 * (bug-c-a-wide-string-literal-truncates-hex-escapes-above-ff).
 *
 * In a wide literal an escape's value is limited by wchar_t, not by char:
 * \x takes every hex digit that follows, and L"\x79C1" is one element
 * 0x79C1. A \u or \U escape names a code point, in narrow literals too, where
 * gcc writes it as UTF-8. Raw UTF-8 source text in L"" becomes one element
 * per character. A wide literal concatenated with a narrow one is wide. */
#include <stdio.h>
#include <wchar.h>

static void dump(const char *what, const wchar_t *w, int n) {
  int i;
  printf("%-10s", what);
  for (i = 0; i < n; i++) printf(" %x", (unsigned)w[i]);
  printf("\n");
}

static void dumpn(const char *what, const char *s, int n) {
  int i;
  printf("%-10s", what);
  for (i = 0; i < n; i++) printf(" %02x", (unsigned char)s[i]);
  printf("\n");
}

int main(void) {
  static const wchar_t arr[] = L"\x79C1\x306F";
  dump("hex", L"\x79C1\x306F", 3);
  dump("hex-cat", L"\x79C1\x306F" "a", 4);
  dump("hex-long", L"\x79C1\x306Fa", 3);
  dump("hex-low", L"\xE9\x41", 3);
  dump("hex-max", L"\x10FFFF\x7FFFFFFF", 3);
  dump("octal", L"\351\101\0z", 4);
  dump("ucn", L"\u00e9\U0001F600\u79C1", 4);
  dump("raw", L"é私😀", 4);
  dump("mixed", L"a\x100" "b" L"\u0301", 5);
  dump("array", arr, 3);
  {
    wchar_t local[] = L"\x79C1\u00e9z\xFFFFFFFF";
    dump("local", local, 5);
    printf("local-sz  %d\n", (int)sizeof(local));
  }
  printf("sizeof    %d %d %d\n", (int)sizeof(L"ab"), (int)sizeof(L"\x79C1"), (int)sizeof(arr));
  printf("chars     %x %x %x %x %x\n", (unsigned)L'\x79C1', (unsigned)L'私', (unsigned)L'\u79c1',
         (unsigned)L'\351', (unsigned)L'\xE9');
  dumpn("narrow-u", "\u00e9\u79C1", 6);
  dumpn("narrow-U", "\U0001F600", 5);
  dumpn("narrow-x", "\xE9\x41\101", 4);
  return 0;
}
