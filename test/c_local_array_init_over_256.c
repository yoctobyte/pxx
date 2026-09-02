/* BLOCK-SCOPE array initialisers past 256 elements — the sibling of
 * test/c_global_array_init_over_256.c, one scope down.
 *
 * ParseCLocalDeclAST held its element columns as 256-entry STACK arrays and
 * past 256 had four different behaviours, three of them silent: the general
 * expression arm refused loudly, the designated arm dropped the whole
 * initialiser, and the string-ROW arm stopped copying MID-ROW and left the
 * tail zero. Row 4 is the one that only the row arm can fail: a whole-array
 * check passes on a truncation.
 *
 * The re-entrancy is why this arm could not use the flat pool the file-scope
 * fix uses: an element expression can be a GNU statement-expression holding
 * another declaration, so the pool is a stack and row 5 is its positive
 * control — the inner 300-element array is parsed while the outer one's
 * elements are half-filled, and both must come out whole.
 *
 * The THRESHOLD is the assertion, not the size: rows 1 and 2 read one table at
 * 256 and at 257, because a test built only at 300 passes on a compiler capped
 * at 400 and tells nobody.
 */
#include <stdio.h>

#define E(n)       0x##n,
#define TEN(p)     E(p##0) E(p##1) E(p##2) E(p##3) E(p##4) \
                   E(p##5) E(p##6) E(p##7) E(p##8) E(p##9)
#define HUNDRED(p) TEN(p##0) TEN(p##1) TEN(p##2) TEN(p##3) TEN(p##4) \
                   TEN(p##5) TEN(p##6) TEN(p##7) TEN(p##8) TEN(p##9)
#define THREE_HUNDRED HUNDRED(0) HUNDRED(1) HUNDRED(2)

static int sum(const int *t, int n)
{
  int i;
  int k = 0;
  for (i = 0; i < n; i++) k += t[i];
  return k;
}

int main(void)
{
  /* 300 ordinary elements: the arm that used to refuse with
     `too many C array initializer elements'. */
  int tab[300] = { THREE_HUNDRED };

  /* the same list as a block-scope STATIC, which takes the other arm */
  static const int stab[300] = { THREE_HUNDRED };

  /* designated range crossing the boundary in one designator */
  int ranged[400] = { [0 ... 399] = 7, [300] = 9 };

  /* a string ROW longer than 256 characters: the arm that TRUNCATES */
  char rows[2][400] = {
    "0123456789012345678901234567890123456789012345678901234567890123"
    "0123456789012345678901234567890123456789012345678901234567890123"
    "0123456789012345678901234567890123456789012345678901234567890123"
    "0123456789012345678901234567890123456789012345678901234567890123"
    "TAIL",
    "second"
  };

  int i;
  int zeros = 0;

  printf("1 %d\n", sum(tab, 256));
  printf("2 %d\n", sum(tab, 257));
  printf("3 %d %d\n", sum(tab, 300), sum(stab, 300));

  for (i = 0; i < 400; i++) if (ranged[i] == 0) zeros++;
  printf("4 %d %d %d\n", zeros, ranged[399], ranged[300]);

  printf("5 %d %s %s\n", (int)sizeof(rows[0]), rows[0] + 256, rows[1]);

  /* RE-ENTRANCY. The inner 300-element declaration is parsed while the outer
     list has two elements in flight. On a flat pool the inner one starts at
     slot 0 and writes over both of them; nest[0] and nest[1] are what says so. */
  {
    int nest[5] = { 11, ({ int in[300] = { THREE_HUNDRED }; sum(in, 300); }), 33, 44, 55 };
    printf("6 %d %d %d %d %d\n", nest[0], nest[1], nest[2], nest[3], nest[4]);
  }
  return 0;
}
