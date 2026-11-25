/* `case K:` and `default:` prefix ONE statement (C 6.8.1), so a case label
   can sit inside an unbraced if and the if still guards that statement:

       default: if (q == 0) case '"': case '$': n += 10;

   is "for '"' and '$' always, for anything else only when q == 0". pxx
   returned the marker as a statement of its own, the if guarded nothing, and
   `n += 10` ran for every character. mksh's tree.c is written exactly so (it
   decides which characters to backslash inside double quotes), and the shell
   then turned `"$(echo 'a b')"` into `\a\ \b`. The expected output is gcc's.
   feature-nodisx-toybox-and-a-posix-shell-built-by-pxx */
#include <stdio.h>

static int quoted(int c, int q) {
  int n = 0;
  switch (c) {
  default:
    if (q == 0)
  case '"':
  case '$':
      n += 10;
    break;
  }
  return n;
}

/* the same with a `name:` label and an else, and a case label as the else */
static int chain(int c, int q) {
  int n = 0;
  switch (c) {
  case 1:
    if (q)
      n += 1;
    else
  case 2:
      n += 2;
    n += 100;
    break;
  default:
    if (q)
  dflt:
      n += 5;
    if (n == 0) { q = 1; goto dflt; }
  }
  return n;
}

/* Duff's device: labels inside a loop body, which always worked */
static int duff(int count) {
  int n = 0, k = (count + 3) / 4;
  switch (count % 4) {
  case 0: do { n++;
  case 3: n++;
  case 2: n++;
  case 1: n++;
          } while (--k > 0);
  }
  return n;
}

int main(void) {
  printf("quoted: %d %d %d %d %d\n", quoted('a', 0), quoted('a', 1),
         quoted('"', 1), quoted('$', 0), quoted('$', 1));
  printf("chain: %d %d %d %d %d\n", chain(1, 1), chain(1, 0), chain(2, 1),
         chain(3, 1), chain(3, 0));
  for (int i = 1; i <= 9; i++) printf("%d ", duff(i));
  printf("\n");
  return 0;
}
