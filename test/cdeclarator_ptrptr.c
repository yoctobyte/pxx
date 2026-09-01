/* A `**' declarator that is not FIRST in its declaration lost its pointee
 * record, so a field write through it went to OFFSET 0.
 *
 * `struct nl **a, **b;' gave `a' the record and `b' REC_NONE. ResolveNodeRec
 * then could not find the field, and `(*b)->n = 22' wrote 22 into `next'
 * instead of `n'. In busybox ash that is the nodelist tail-append: the parsed
 * command was stored into ->next rather than ->n, and the command substitution
 * evaluated a garbage node. Found attempting rung 2
 * (feature-c-corpus-busybox-multi-applet).
 *
 * POSITION IS WHAT DECIDED IT, not uniformity, which is why the mixed row is
 * here: `struct nl *m1, **m2;' broke only m2, and every single-star sibling was
 * always fine. A test using only `**a, **b' would pass with a fix that keyed on
 * the declaration being uniformly double-star.
 *
 * The first-declarator arm of this same bug had already been fixed once, with a
 * lua repro; the three sibling sites were left behind. Rows 1 and 4 are the
 * already-working arms and are kept so a regression there is not silent.
 */
#include <stdio.h>

struct nl { struct nl *next; int n; };
static struct nl node;
static struct nl *one = &node;

static void reset(void) { node.next = 0; node.n = 0; }
static void show(const char *tag) {
  printf("%s n=%d next=%d\n", tag, node.n, node.next != 0);
}

int main(void) {
  struct nl *s1, *s2;            /* single star, two declarators */
  struct nl **d1, **d2, **d3;    /* double star, three declarators */
  struct nl *m1, **m2;           /* MIXED depth in one declaration */

  s1 = &node; s2 = &node;
  d1 = &one;  d2 = &one; d3 = &one;
  m1 = &node; m2 = &one;

  reset(); s1->n      = 1; show("1");
  reset(); s2->n      = 2; show("2");
  reset(); (*d1)->n   = 3; show("3");
  reset(); (*d2)->n   = 4; show("4");   /* was: wrote into next */
  reset(); (*d3)->n   = 5; show("5");   /* was: wrote into next */
  reset(); m1->n      = 6; show("6");
  reset(); (*m2)->n   = 7; show("7");   /* was: wrote into next */
  return 0;
}
