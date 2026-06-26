/* Comma operator at expression top-level in if/while/for conditions
   (lua llex: `while (cast_void(save_and_next(ls)), lisxdigit(ls->current))`).
   Exit 42. */
int side = 0;
int bump(void) { side++; return 0; }
int main(void) {
  int i = 0;
  while (bump(), i < 5) i++;     /* loops 5x; side becomes 6 (incl final test) */
  int n = 0;
  if (bump(), i == 5)           /* condition uses the second operand */
    n = 40;
  for (i = 0; (bump(), i < 2); i++) n++;   /* n += 2 -> 42 */
  return n;
}
