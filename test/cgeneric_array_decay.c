/* _Generic over an ARRAY controlling expression: the type is the one after
   array-to-pointer decay (C11 6.5.1.1p2, as gcc and clang implement it).

   audit-a-typekind-tyrecord-is-not-a-guard-against-an-array-symbol

   CExprCG had no array shape at all, so an array symbol fell through to its
   TypeKind -- which for an array holds the ELEMENT's kind. `struct S a[3]`
   reached the tyRecord arm and became a bare cgStruct; `int b[4]` became a
   plain cgInt. Measured against `gcc -std=c11` on this file, before and after:

       controlling expr   gcc      before   after
       struct S a[3]      S*       default  S*
       int      b[4]      i*       i        i*
       char     c[5]      c*       c        c*
       long     L[2]      L*       L        L*
       int      m[2][3]   default  i        default

   The int/char/long rows never touched RecName, which is why this arm is wider
   than the guard that exposed it. The m[2][3] row is the reason the inner
   dimensions are modelled as nested array levels rather than flattened: `int
   (*)[3]` matches neither `int *` nor `int`, so gcc takes `default`, and a
   flattened descriptor answered `int *` -- a CONFIDENT wrong selection.

   Two rows are still not gcc's and are filed rather than fixed here (they need
   carriers the symbol does not have): `int *p[2]` wants `int **` and the
   element's pointer target is not recorded, and `const int ci[2]` wants
   `const int *` and element constness is not recorded either.

   Exit code, not stdout, so the assertion does not depend on puts. */
struct S { int x; };

int main(void)
{
  struct S a[3];
  int  b[4];
  char c[5];
  long L[2];
  int  m[2][3];
  struct S one;
  int scal;
  int score = 0;

  score += _Generic(a, struct S *: 1, struct S: 0, default: 0);
  score += _Generic(b, int  *: 2, int : 0, default: 0);
  score += _Generic(c, char *: 4, char: 0, default: 0);
  score += _Generic(L, long *: 8, long: 0, default: 0);
  /* the DEFAULT arm is the correct one here: m decays to int (*)[3] */
  score += _Generic(m, int *: 0, int: 0, default: 16);
  /* controls: the non-array spellings must be untouched */
  score += _Generic(one,  struct S *: 0, struct S: 32, default: 0);
  score += _Generic(scal, int *: 0, int: 64, default: 0);

  (void)a; (void)b; (void)c; (void)L; (void)m; (void)one; (void)scal;
  return score;   /* 127 */
}
