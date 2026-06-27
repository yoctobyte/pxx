/* sizeof("lit") is the char-array size (byte length + NUL), not the pointer
   size. lua's new_localvarliteral registers a hidden local of length
   sizeof(name)-1; the pointer-size default corrupted "self" (len 7 not 4), so
   colon-method `self` resolved to a nil global and all lua OOP broke. */
int main(void) {
  int a = (int)sizeof("hello");     /* 6 */
  int b = (int)(sizeof("self") - 1);/* 4 */
  int c = (int)sizeof("");          /* 1 */
  return (a == 6 && b == 4 && c == 1) ? 42 : 1;
}
