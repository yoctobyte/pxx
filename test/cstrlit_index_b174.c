/* Regression: indexing a string literal is a char[] access — 0-based, single
   byte, zero-extended. Was: wrong offset (Pascal 1-based -7) AND a 4-byte load
   (CNodePointeeTk defaulted to int), so `int c = "abc"[0]` != 'a' (adjacent
   chars leaked into the high bits) and the offset was off by one. */
int main(void){
  if ("ABC"[0] != 'A') return 1;
  if ("ABC"[2] != 'C') return 2;
  int c = "ABC"[0];              /* stored to a wider int: must be clean 65 */
  if (c != 65) return 3;
  if (c == 65) { } else return 4;
  const char *v = "1.3.1";
  if (v[0] != '1' || v[4] != '1') return 5;
  return 42;
}
