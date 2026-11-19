/* gcc's alternate spellings of `signed`: `__signed__` and `__signed`
   (e2fsprogs ext2_types.h: `typedef __signed__ short __s16`). They are
   keywords, not macros, so `#ifdef __signed__` stays false.
   bug-c-the-signed-keyword-spelling-dunder-signed-is-not-recognised */
#include <stdio.h>

typedef __signed__ char s8;
typedef __signed char s8b;
typedef __signed__ short s16;
typedef __signed__ int s32;
typedef __signed__ long long s64;

int main(void)
{
  s8 a = -5; s8b b = -6; s16 c = -7; s32 d = -8; s64 e = -9;
  __signed__ x = -10;
  __signed y = -11;
  unsigned char raw = 0xF0;
  printf("%d %d %d %d %lld %d %d\n", a, b, c, d, e, x, y);
  printf("%d %d %d\n", (int)sizeof(s8), (int)sizeof(s16), (int)sizeof(s64));
  printf("%d\n", (int)(__signed__ char)raw);
#ifdef __signed__
  printf("__signed__ is a macro\n");
#else
  printf("__signed__ is not a macro\n");
#endif
  return 0;
}
