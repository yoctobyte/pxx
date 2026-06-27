/* Scalar `const char *p = "literal";` global initializer (regression: the
   pointer stayed NULL, so lua's `const char *const CLIBS = "_CLIBS"` made
   `lua_getfield(registry, CLIBS)` dereference a null key). Adjacent string
   literals concatenate. */

static unsigned long slen(const char *s) { unsigned long n = 0; while (s && s[n]) n++; return n; }

const char *const tag = "_CLIBS";
const char *msg = "ab" "cd";   /* adjacent-literal concat -> "abcd" */

int main(void) {
  if (tag == 0) return 1;
  if (msg == 0) return 2;
  if (tag[0] != '_' || tag[1] != 'C') return 3;
  if (msg[0] != 'a' || msg[3] != 'd') return 4;
  /* "_CLIBS"(6) + "abcd"(4) = 10... wait want 42 */
  return (int)(slen(tag) + slen(msg)) + 32;   /* 6 + 4 + 32 = 42 */
}
