/* A function-macro / function call whose arguments span multiple physical lines
   must work (the preprocessor was line-based). lua/sqlite use multi-line
   api_check / luaL_error calls. Exit 42. */
#define ADD3(a, b, c) ((a) + (b) + (c))
int realadd(int a, int b) { return a + b; }
int main(void) {
  int x = ADD3(10,
               20,
               2);          /* macro args across 3 lines -> 32 */
  int y = realadd(4,
                  6);        /* plain call across 2 lines -> 10 */
  return x + y;             /* 32 + 10 = 42 */
}
