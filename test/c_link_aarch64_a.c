/* pascal26 --link on aarch64: two objects, no ld (with c_link_aarch64_b.c).
 *
 * What crosses the seam: a call into the other object, a global read and
 * written from both sides, a pointer to the other object's data stored in
 * this object's data (an ABS64 slot), a function pointer table, and a string
 * pointer table. The synthesised _start must hand main argc/argv, run the
 * .init_array (environ comes from the init thunk, so getenv is the witness),
 * and turn main's return value into the exit status.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int bump(int by);
extern int shared;
extern const char *names[3];
extern int (*ops[2])(int, int);
int *where = &shared;              /* ABS64 against the other object's .data */

int main(int argc, char **argv) {
  int i, r;
  r = bump(5);
  *where += 100;
  printf("argc %d argv1 %s\n", argc, argc > 1 ? argv[1] : "-");
  printf("bump %d shared %d\n", r, shared);
  for (i = 0; i < 3; i++) printf("name %s\n", names[i]);
  printf("ops %d %d\n", ops[0](6, 7), ops[1](6, 7));
  printf("env %s\n", getenv("PXX_LINK_A64") ? getenv("PXX_LINK_A64") : "(none)");
  printf("strlen %d\n", (int)strlen(argv[0]) > 0);
  return 3;
}
