/* `(char*)"abc"` pointed at the string's 8-byte LENGTH PREFIX, not its data --
   silently, and `(char*)"lit"` is everywhere in real C (casting away const to
   reach a non-const API):

     const char *a = "abc";
     char       *b = (char*)"abc";
     b - a;      / * gcc: 0     pxx: -8 * /
     b[0];       / * gcc: 'a'   pxx: 3  (the length word) * /
     printf("%s", b);   / * gcc: abc   pxx: (empty) * /

   A string literal's IR value is the frozen string's HANDLE, and each consumer
   skips the prefix by testing `ASTKind[...] = AN_STR_LIT` on its own operand --
   the assign path, the return path and the call-argument marshalling each carry
   their own copy of that +8. An AN_PTR_CAST in between is not an AN_STR_LIT, so
   every one of those tests missed at once.

   In C a string literal already IS a `char *`, so a pointer cast of one is an
   identity; the cast now yields the literal unchanged, which removes a shape
   instead of adding a fourth copy of the skip. The producer-side normalisation
   is filed as refactor-c-string-literal-decay-belongs-at-the-producer.

   Every expectation is gcc -O0's.
   bug-c-a-pointer-cast-of-a-string-literal-points-at-the-length-prefix */
#include <stdio.h>
#include <string.h>

static char *gp = (char*)"glob";
static const char *gq = "glob";

static char *ret_cast(void) { return (char*)"ret"; }
static int take(const char *s) { return (int)strlen(s) * 10 + s[0]; }

int main(void) {
  const char *a = "abc";
  char *b = (char*)"abc";
  char *c = (char*)(void*)"abc";
  const char *d = (const char*)"abc";
  unsigned char *u = (unsigned char*)"abc";

  printf("same %ld %ld %ld %ld\n", (long)(b - a), (long)(c - a), (long)(d - a),
         (long)((const char*)u - a));
  printf("bytes %d %d %d %d\n", b[0], b[1], b[2], b[3]);
  printf("len %zu %zu %zu\n", strlen(b), strlen(c), strlen(d));
  printf("str [%s] [%s] [%s]\n", b, c, d);
  printf("global %ld [%s]\n", (long)(gp - gq), gp);
  printf("index %c %c\n", ((char*)"xyz")[1], ((const char*)"xyz")[2]);
  printf("inline [%s] [%s]\n", (char*)"inline", "uncast");
  printf("concat [%s]\n", (char*)("a" "b"));
  printf("ret [%s] %zu\n", ret_cast(), strlen(ret_cast()));
  printf("arg %d %d\n", take((char*)"abc"), take("abc"));
  printf("cmp %d %d\n", strcmp(b, "abc"), strcmp((char*)"abc", a));
  printf("empty %zu %d\n", strlen((char*)""), ((char*)"")[0]);
  return 0;
}
