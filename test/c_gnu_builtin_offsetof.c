/* gcc's __builtin_offsetof(TYPE, DESIGNATOR), and offsetof with subscripts
   in the designator, in expressions and in static initialisers (NetBSD's
   rump sources call the builtin by name). A subscripted member in a static
   initialiser used to hang the compiler. The output is gcc's. */
#include <stdio.h>
#include <stddef.h>

struct in { short x; int y[4]; };
struct s { int a; char b[3]; struct in n; double z; struct in arr[3]; int m[2][5]; };

static unsigned long tab[] = {
  __builtin_offsetof(struct s, b[2]),
  __builtin_offsetof(struct s, n.y[3]),
  __builtin_offsetof(struct s, z),
  __builtin_offsetof(struct s, arr[2].y[1]),
  __builtin_offsetof(struct s, m[1][3]),
  offsetof(struct s, n.y[1]),
};

int main(void) {
  unsigned i;
  printf("%lu %lu %lu %lu %lu\n",
         (unsigned long)__builtin_offsetof(struct s, a),
         (unsigned long)__builtin_offsetof(struct s, b),
         (unsigned long)__builtin_offsetof(struct s, b[2]),
         (unsigned long)__builtin_offsetof(struct s, arr[1].x),
         (unsigned long)__builtin_offsetof(struct s, m[1][3]));
  for (i = 0; i < sizeof tab / sizeof tab[0]; i++) printf("%lu ", tab[i]);
  printf("\n");
  return 0;
}
