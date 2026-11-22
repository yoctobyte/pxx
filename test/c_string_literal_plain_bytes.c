/* C string literals as plain bytes and a NUL (InternCStr), against gcc: indexing,
 * deref, sizeof, concatenation, embedded NULs, one copy per text, literals in
 * globals, returned, and offset. Each was a managed-string handle with a
 * 32-byte header and 8-byte alignment before.
 * feature-c-toybox-size-gap-literal-headers-call-realign-no-regalloc */
#include <stdio.h>
#include <string.h>
static const char *g1 = "global";
static const char *g2[] = { "alpha", "beta", "alpha" };
static char arr[] = "array";
const char *f(int i) { return i ? "yes" : "no"; }
int main(void) {
  const char *a = "same", *b = "same";
  printf("%c %c %d\n", "abc"[1], *"xyz", (int)sizeof "hello");
  printf("%s %s %s %s\n", g1, g2[0], g2[2], arr);
  printf("%d %d\n", a == b, (int)strlen("ab" "cd" "ef"));
  printf("%s %s\n", f(1), f(0));
  printf("%d\n", (int)strlen("emb\0ed"));
  printf("%d %d\n", memcmp("a\0b", "a\0b", 3), (int)sizeof("a\0b"));
  printf("%s\n", 1 + "skip");
  return 0;
}
