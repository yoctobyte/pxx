/* C conditional operator `?:` — nested, right-associative, and only the taken
   branch is evaluated (the `side` effect proves no double-evaluation). Exit 37. */
int main(void) {
  int n = 3, m = 8;
  int a = (n <= m) ? n : m;                       /* 3  */
  int b = (n > m) ? 100 : 7;                      /* 7  */
  int c = n ? (m ? 5 : 6) : 9;                    /* 5  (nested) */
  int side = 0;
  int d = (n == 3) ? (side = 11) : (side = 22);   /* taken branch only -> side=11, d=11 */
  return a + b + c + d + side;                    /* 3+7+5+11+11 = 37 */
}
