/* Regression: GNU/C99 range designators [lo ... hi] = v in a local aggregate
   initializer fill every index lo..hi with the one value. Part of the
   c-testsuite 00216 init battery (bug-c-abi-battery / feature-c-compound-literals).
   The recursive aggregate-init walker (CInitWalkArray) now expands a range in the
   `[` designator branch. */
struct T { unsigned char s[16]; unsigned char a; };
int main(void) {
  struct T t = { { [1 ... 5] = 9, [6 ... 10] = 3, [4 ... 7] = 4 }, 1 };
  int i, ok = 1;
  /* overlapping ranges resolve left-to-right: [1..5]=9, [6..10]=3, [4..7]=4 */
  unsigned char expect[16] = {0,9,9,9,4,4,4,4,3,3,3,0,0,0,0,0};
  for (i = 0; i < 16; i++) if (t.s[i] != expect[i]) ok = 0;
  if (t.a != 1) ok = 0;
  return ok ? 42 : 1;
}
