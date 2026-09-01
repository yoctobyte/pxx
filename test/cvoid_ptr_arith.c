/* Arithmetic on `void *' must step ONE BYTE per unit.
 *
 * `void' has no size in ISO C, so `void *' arithmetic is a GNU extension that
 * gcc and clang both define as sizeof(void) == 1. crtl's headers and every real
 * C program lean on it. pxx scaled by FOUR, because `void' is parsed as a
 * tyInteger PLACEHOLDER and the pointer suffix overrode the NODE's type to
 * tyPointer while leaving the ELEMENT type holding the placeholder.
 *
 * ROW 5 IS WHY THIS WAS HARD TO SEE. Casting first -- `(char *)v + n' -- was
 * always right, and that is the spelling most code uses. Only the uncast form
 * was wrong, so a program can use both idioms and have half its pointer
 * arithmetic silently land four times too far.
 *
 * busybox ash is built on the uncast form: `#define stackblock() ((void*)g_stacknxt)'
 * and then `stackblock() + strloc' throughout the expansion code, right beside
 * `startp = (char *)stackblock() + startloc' which casts and was fine. With
 * strloc=7 the uncast one landed 28 bytes in, so `${x:2:3}' read its POS:LEN
 * spec from the wrong place and produced the variable, the literal spec and a
 * run of garbage as three separate words -- which reads as a PARSER bug, and is
 * not one. Found attempting rung 2 (feature-c-corpus-busybox-multi-applet).
 *
 * Row 8 is the boundary in the other direction: `void **' has a POINTER
 * element, so it must keep the 8-byte stride and NOT become 1. A fix that
 * blanket-forces stride 1 for anything mentioning void passes rows 1-7 and
 * breaks that one.
 */
#include <stdio.h>

static char buf[64];
#define blk() ((void *)buf)

int main(void) {
  void *v = (void *)buf;
  char *c = buf;
  void *vv[4];
  void **pv = &vv[0];
  int n = 7;

  printf("1 %d\n", (int)((char *)(v + n) - buf));      /* was 28 */
  printf("2 %d\n", (int)((char *)(blk() + n) - buf));  /* was 28 -- ash's idiom */
  printf("3 %d\n", (int)((c + n) - buf));              /* char*: always right */
  printf("4 %d\n", (int)((char *)(v + 1) - buf));      /* was 4 */
  printf("5 %d\n", (int)(((char *)v + n) - buf));      /* cast first: always right */

  { void *w = v; w += 3;
    printf("6 %d\n", (int)((char *)w - buf)); }        /* was 12 */

  { const void *cv = buf;
    printf("7 %d\n", (int)((const char *)(cv + 5) - buf)); }  /* was 20 */

  /* void** : the element IS a pointer, so the stride stays 8 */
  printf("8 %d\n", (int)((char *)(pv + 1) - (char *)pv));

  /* difference between two void* is in bytes, both before and after */
  printf("9 %d\n", (int)((v + 7) - v));
  return 0;
}
