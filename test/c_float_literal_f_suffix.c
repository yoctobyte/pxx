/* The `f` suffix on a float literal was IGNORED: `0.1f` kept the nearest
   DOUBLE to 0.1, and `16777217.0f` kept 16777217.0. Not a display question --
   16777217 is the smallest integer a float cannot represent, so row F is a
   comparison a program can branch on, and it answered true where C says false.

   Every expected value here is target-independent arithmetic and matches gcc on
   all five targets, so a row that disagrees is wrong by construction.

   Rows A/C/E are the CONTROL and were always green: a store into a float lvalue
   rounds, and an explicit `(float)` cast rounds. Keeping them is the point --
   they are what says the machinery existed and only the suffix arm was missing,
   which is the sibling rule in normalise-dont-special-case.md. Dropping them
   turns this back into the two mystery rows it was filed as.

   G is the TYPE half and is a separate mechanism from the value: `0.1f` is a
   float, so sizeof is 4. The value rows can be green with G still red -- they
   were, for one build -- so G is not redundant with B.

   I and J are the same defect through the shapes that skip the plain-decimal
   scanner: an exponent form, and the capital `F`. A suffix handler that only
   sees `1.0f` is the second path that stays broken.

   bug-c-the-f-suffix-on-a-float-literal-is-ignored */

#include <stdio.h>

int main(void)
{
  float v = 0.1f;

  printf("A %.9f\n", (double)v);                  /* store into float rounds  */
  printf("B %.9f\n", (double)0.1f);               /* THE BUG: suffix ignored  */
  printf("C %.9f\n", (double)(float)0.1);         /* explicit cast rounds     */
  printf("D %.1f\n", (double)16777217.0f);        /* THE BUG, exactly         */
  printf("E %.1f\n", (double)(float)16777217.0);  /* the cast gets it right   */
  printf("F %d\n", 16777217.0f == 16777217.0);    /* branchable, not display  */
  printf("G %d\n", (int)sizeof(0.1f));            /* the TYPE half            */
  printf("H %d\n", (int)sizeof(0.1));             /* unsuffixed stays double  */
  printf("I %.9f\n", (double)1e-1f);              /* exponent form            */
  printf("J %.9f\n", (double)0.1F);               /* capital F                */
  return 0;
}
