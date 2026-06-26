/* Adjacent string-literal concatenation: C `"a" "b"` == `"ab"`. lua's
   lua_pushliteral expands to `"" s`. Exit 42. (Uses the concatenated literals
   directly — string-literal-to-pointer-var assignment is a separate bug.) */
int len(const char *s) { int n = 0; while (*s) { n++; s++; } return n; }
int eq(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a == *b; }
int main(void) {
  int la = len("foo" "bar" "baz");        /* 9 */
  int lb = len("" "hello");               /* 5 */
  int ok = eq("foobarbaz", "foo" "bar" "baz") && eq("hello", "" "hello");
  return la * 2 + lb + 19 + (ok ? 0 : 100);   /* 18 + 5 + 19 = 42 */
}
