/* sizeof of a parenthesised string literal that is 8 bytes with its NUL --
   the same as the pointer-size default the operand walk starts from -- was
   re-parsed as an expression and answered 4. fontconfig's gperf pool
   (`char str[sizeof("charset")]`) came out short and its built-in object
   lookup failed. bug-c-sizeof-of-a-parenthesised-7-character-literal-is-4 */
#include <stdio.h>
#include <stddef.h>
struct Pool {
  char s1[sizeof("hash")];
  char s2[sizeof("charset")];
  char s3[sizeof("foundry")];
  char s4[sizeof("globaladvance")];
};
static const struct Pool pool = { "hash", "charset", "foundry", "globaladvance" };
int g7 = sizeof("abcdefg");
int main(void)
{
  const char *base = (const char *)&pool;
  int l7 = sizeof("abcdefg");
  printf("%d %d %d %d\n", g7, l7, (int)sizeof("abc" "defg"), (int)sizeof("abcdefg"[0]));
  printf("%d %d %d %d\n", (int)sizeof(struct Pool), (int)offsetof(struct Pool, s3),
         (int)offsetof(struct Pool, s4), (int)sizeof "abcdefg");
  printf("%s %s %s\n", base + offsetof(struct Pool, s2), base + offsetof(struct Pool, s3),
         base + offsetof(struct Pool, s4));
  return 0;
}
