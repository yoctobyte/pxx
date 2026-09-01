/* C 6.5.6: POINTER MINUS POINTER IS ptrdiff_t, AN INTEGER.
 *
 * The C parser tagged `p - q' by asking about the LEFT operand alone, so the
 * DIFFERENCE came out tagged tyPointer -- and everything downstream that reads
 * the tag then treated it as a pointer. The next operator scaled against it:
 * `q - p + 1' on a char** one element apart evaluated as 1 + (1 * 8) = 9.
 *
 * WHY THE ISOLATED SHAPES ARE THE POINT OF THIS FILE. Rows 1, 2 and 8 were
 * ALWAYS RIGHT: the subtraction itself was never broken, only its result type,
 * so a probe that computes a pointer difference and prints it passes every row
 * and finds nothing. I wrote exactly that probe first -- six shapes, all green
 * -- and it said the compiler was fine. What found this was instrumenting
 * busybox's own getopts and seeing `diff=1' and `ind=9' printed from the SAME
 * expression, a contradiction no isolated repro can produce because the defect
 * only appears when a SECOND operator consumes the difference.
 *
 * Row 6 is the discriminator against the obvious wrong fix: multiplication
 * never scales, so `(q-p)*2' was always 2, and a fix that suppressed scaling
 * only where it looked wrong would leave rows 3-5 to some other rule.
 *
 * In ash this is `ind = optnext - optfirst + 1' in getopts: OPTIND became 9
 * instead of 2, never advanced, getopts returned the same option forever and
 * `while getopts ...; do' SPUN -- hanging the rung-2 harness twice, for 39 and
 * 22 minutes, printing nothing at all. Found attempting rung 2
 * (feature-c-corpus-busybox-multi-applet).
 *
 * The vararg row matters on ILP32 and not here: ptrdiff_t is POINTER-WIDTH, and
 * the variadic push believes the node's tag
 * (bug-a-pointer-difference-as-vararg-pushes-8-bytes-on-32bit fixed the IR's
 * half; this is the AST tag that the IR was having to correct).
 */
#include <stdio.h>

static char *sv[6];
static int   iv[6];

int main(void) {
  char **a = &sv[0], **b = &sv[1];   /* ONE ELEMENT apart = 8 bytes */
  int *ia = &iv[0], *ib = &iv[3];    /* three elements = 12 bytes */
  int r;
  long L;

  printf("1 %d\n", (int)(b - a));          /* always worked */
  r = b - a;          printf("2 %d\n", r); /* always worked */
  r = b - a + 1;      printf("3 %d\n", r); /* was 9 */
  r = (b - a) + 1;    printf("4 %d\n", r); /* was 9 */
  r = 1 + (b - a);    printf("5 %d\n", r); /* was 9 */
  r = (b - a) * 2;    printf("6 %d\n", r); /* always worked -- discriminator */
  L = b - a + 1;      printf("7 %d\n", (int)L);  /* was 9 */
  printf("8 %d\n", (int)(b - a + 1));      /* was 9 */

  /* a stride other than 8, so a fix that hardcodes the pointer size shows up */
  printf("9 %d\n",  (int)(ib - ia));
  r = ib - ia + 1;    printf("10 %d\n", r);
  r = (ib - ia) - 1;  printf("11 %d\n", r);

  /* the difference as a vararg: pointer-width, and the push reads the tag */
  printf("12 %d %d\n", (int)(b - a), 7);
  return 0;
}
