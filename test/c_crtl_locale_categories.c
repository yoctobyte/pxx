/* crtl: the <locale.h> category numbers.
 *
 * A CONSTANT THAT ONLY EVER REACHES OUR OWN IGNORING STUB LOOKS FREE TO CHOOSE.
 * It is not. crtl had LC_ALL = 0 and LC_NUMERIC = 4, which are glibc's LC_CTYPE
 * and LC_MONETARY, and crtl's setlocale ignores the category so nothing in this
 * runtime could tell. But a pxx --emit-obj object is LINKED BY GCC in the
 * busybox build, and the constant compiled from this header then reaches the
 * real setlocale: `setlocale(LC_ALL, value)' in ash.c would have set LC_CTYPE
 * alone, and `setlocale(LC_NUMERIC, "C")' in libbb/duration.c would have set
 * LC_MONETARY. No diagnostic anywhere.
 *
 * Row 1 and 2 are therefore diffed against glibc's own headers, which is the
 * only instrument that can see this. LC_COLLATE, LC_CTYPE, LC_MONETARY and
 * LC_TIME were also simply MISSING, which under pxx is a warning and a zero,
 * not an error -- lua's loslib.c and lstrlib.c have compiled through all four
 * on every target and passed, because 0 is a real category and lua's setlocale
 * ignores it too.
 *
 * Row 3 pins crtl's own answer rather than glibc's, and is the one row that is
 * NOT an oracle comparison: this runtime has a fixed "C" locale.
 */
#include <stdio.h>
#include <locale.h>
#include <string.h>

int main(void)
{
  struct lconv *lc;

  printf("1 %d %d %d %d %d %d %d\n", LC_CTYPE, LC_NUMERIC, LC_TIME, LC_COLLATE,
         LC_MONETARY, LC_MESSAGES, LC_ALL);
  printf("2 %d %d %d %d %d %d\n", LC_PAPER, LC_NAME, LC_ADDRESS, LC_TELEPHONE,
         LC_MEASUREMENT, LC_IDENTIFICATION);

  /* Every category is distinct -- the property that was broken, and the one a
     list of twelve numbers is easy to break again by editing one line. */
  {
    int cats[13];
    int i, j, dup = 0;
    cats[0] = LC_CTYPE; cats[1] = LC_NUMERIC; cats[2] = LC_TIME;
    cats[3] = LC_COLLATE; cats[4] = LC_MONETARY; cats[5] = LC_MESSAGES;
    cats[6] = LC_ALL; cats[7] = LC_PAPER; cats[8] = LC_NAME;
    cats[9] = LC_ADDRESS; cats[10] = LC_TELEPHONE; cats[11] = LC_MEASUREMENT;
    cats[12] = LC_IDENTIFICATION;
    for (i = 0; i < 13; i++)
      for (j = i + 1; j < 13; j++)
        if (cats[i] == cats[j]) dup++;
    printf("3 %d\n", dup);
  }

  lc = localeconv();
  printf("4 %d %d\n", lc != 0, lc != 0 && strcmp(lc->decimal_point, ".") == 0);
  return 0;
}
