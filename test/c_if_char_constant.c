/* A character constant in #if is an int (C 6.10.1p4). pxx had no arm for
   one and read every one as 0, so gperf's charset guard in busybox kconfig
   (zconf.hash.c) hit its #error. .expected is gcc's output. The "truth" row
   is not discriminating on its own: the old evaluator reached 1 by accident. */
#include <stdio.h>
#define R(name, cond) printf("%-10s %d\n", name, cond);
int main(void) {
#if ' ' == 32 && 'A' == 65 && '~' == 126
  R("ascii", 1)
#else
  R("ascii", 0)
#endif
#if '\n' == 10 && '\t' == 9 && '\\' == 92 && '\'' == 39 && '"' == 34
  R("escapes", 1)
#else
  R("escapes", 0)
#endif
#if '\x41' == 65 && '\101' == 65 && '\0' == 0 && '\7' == 7
  R("numeric", 1)
#else
  R("numeric", 0)
#endif
#if !'\0' && 'a' && ('b' - 'a') == 1
  R("truth", 1)
#else
  R("truth", 0)
#endif
#if L'A' == 65 && u'A' == 65 && U'A' == 65
  R("prefixed", 1)
#else
  R("prefixed", 0)
#endif
#define CH 'Z'
#if CH == 90
  R("viamacro", 1)
#else
  R("viamacro", 0)
#endif
  /* the lexer path, unchanged by the refactor */
  printf("lex %d %d %d %d %d\n", 'A', '\n', '\x41', '\101', '\'');
  return 0;
}
