/* The sibling of c_obj_static_link_a.c -- same two `static' names, different
   bodies on purpose. See that file's header for what the difference proves. */
#include <stdio.h>

static int shared_counter = 200;

static int shared_helper(int x) { return x + 2000; }

extern int a_probe(void);

int b_probe(void) { return shared_helper(shared_counter); }

int main(void) {
  printf("a %d\n", a_probe());
  printf("b %d\n", b_probe());
  return 0;
}
