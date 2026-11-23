/* A mode(..) after one declarator of several: gcc applies it to that one
 * declarator only, and pxx gives siblings one base type, so it is refused by
 * name instead of being widened to `b`. */
int a __attribute__((mode(QI))), b;
int main(void) { return sizeof b; }
