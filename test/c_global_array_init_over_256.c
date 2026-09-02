/* FILE-SCOPE array initialisers past 256 elements.
 *
 * ParseCGlobalVarDecl held its element columns as 256-entry STACK arrays and,
 * one element past the end, set nArrElems := -1 and took the whole-array SKIP
 * path: no diagnostic, the array sized to ONE element, the initialiser gone.
 *
 * Measured 2026-09-02 on busybox. include/applet_tables.h is GENERATED, one
 * `<applet>_main' per applet, so `int (*const applet_main[])(int, char**)' has
 * exactly as many entries as the tree was configured for. At 141 applets the
 * whole build was byte-identical to gcc; at 257 all 400 objects still compiled
 * and LINKED, and then every applet that did real work segfaulted through a
 * one-element table. 256 is not a number the generator knows about.
 *
 * The threshold is the assertion. Rows 1 and 2 are the same table read at 256
 * and at 257 entries -- a test built only at 300 would pass on a compiler
 * capped at 400 and tell nobody. Row 4 is the designated-RANGE arm, which had
 * its own separate `nArrElems <= 255' guard that stopped replicating silently
 * mid-range rather than bailing, so a range crossing the boundary left the
 * tail zero -- a null function pointer, i.e. a jump to 0.
 *
 * The functions return their own name read as HEX (0x000 .. 0x299): decimal
 * would make f019's body the invalid octal 019, and a table where every entry
 * points at ONE function passes any row that only sums a constant.
 */
#include <stdio.h>

#define F(n)       static int f##n(void) { return 0x##n; }
#define TEN(p)     F(p##0) F(p##1) F(p##2) F(p##3) F(p##4) \
                   F(p##5) F(p##6) F(p##7) F(p##8) F(p##9)
#define HUNDRED(p) TEN(p##0) TEN(p##1) TEN(p##2) TEN(p##3) TEN(p##4) \
                   TEN(p##5) TEN(p##6) TEN(p##7) TEN(p##8) TEN(p##9)
HUNDRED(0)
HUNDRED(1)
HUNDRED(2)

#undef F
#undef TEN
#undef HUNDRED
#define F(n)       f##n,
#define TEN(p)     F(p##0) F(p##1) F(p##2) F(p##3) F(p##4) \
                   F(p##5) F(p##6) F(p##7) F(p##8) F(p##9)
#define HUNDRED(p) TEN(p##0) TEN(p##1) TEN(p##2) TEN(p##3) TEN(p##4) \
                   TEN(p##5) TEN(p##6) TEN(p##7) TEN(p##8) TEN(p##9)

/* 300 entries -- the busybox shape, one function pointer per generated row. */
int (*const tab[])(void) = {
  HUNDRED(0)
  HUNDRED(1)
  HUNDRED(2)
};

#undef F
#define F(n)       "s" #n,
#undef TEN
#define TEN(p)     F(p##0) F(p##1) F(p##2) F(p##3) F(p##4) \
                   F(p##5) F(p##6) F(p##7) F(p##8) F(p##9)
#undef HUNDRED
#define HUNDRED(p) TEN(p##0) TEN(p##1) TEN(p##2) TEN(p##3) TEN(p##4) \
                   TEN(p##5) TEN(p##6) TEN(p##7) TEN(p##8) TEN(p##9)

/* 300 string-literal elements -- the other capped column (offset + length). */
const char *const strs[] = {
  HUNDRED(0)
  HUNDRED(1)
  HUNDRED(2)
};

/* The designated-range arm, crossing the boundary in one designator. */
int (*const ranged[400])(void) = {
  [0 ... 399] = f001,
  [300] = f002,
};

static int sum_upto(int n)
{
  int i;
  int k = 0;
  for (i = 0; i < n; i++) k += tab[i]();
  return k;
}

int main(void)
{
  int i;
  int nulls = 0;

  printf("1 %d\n", sum_upto(256));
  printf("2 %d\n", sum_upto(257));
  printf("3 %d %d\n", sum_upto(300), (int)(sizeof(tab) / sizeof(tab[0])));

  for (i = 0; i < 400; i++) if (ranged[i] == 0) nulls++;
  printf("4 %d %d %d\n", nulls, ranged[399] ? ranged[399]() : -1,
         ranged[300] ? ranged[300]() : -1);

  printf("5 %d %s %s %s\n", (int)(sizeof(strs) / sizeof(strs[0])),
         strs[0], strs[256], strs[299]);
  return 0;
}
