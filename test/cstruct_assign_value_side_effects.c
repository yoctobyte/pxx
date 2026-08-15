/* A STRUCT assignment used as a VALUE must run its right-hand side exactly
   ONCE — the aggregate half of the rule cassign_value_b43.c pins for scalars.

   It ran twice. `y = (x = f())` lowers to copy_rec(x, call) and
   copy_rec(y, <that copy_rec node>): the inner node is a statement in the IR
   list AND an operand of the outer one, so the emitter walked it at top level
   and again as the outer's source, calling f() twice. Every VALUE still came
   out right — only the side effects doubled — which is why the whole
   real-world C corpus (lua, sqlite, tcc, zlib, c-testsuite) missed it and a
   csmith checksum found it: seed 90202 called a function that mutates a global
   three times where gcc called it twice.
   bug-c-a-struct-assignment-used-as-a-value-runs-its-rhs-twice

   Exit 0 on agreement; each check exits with its own number so a failure says
   which shape broke. Verified against gcc on the same source. */
#include <stdio.h>

struct S { int a; int b; };

static int calls = 0;

static struct S f(void) {
  struct S s;
  calls++;
  s.a = 1;
  s.b = 2;
  return s;
}

int main(void) {
  struct S x, y, z, *p = &x;

  calls = 0; y = (x = f());
  if (calls != 1 || y.a != 1 || y.b != 2 || x.a != 1 || x.b != 2) return 1;

  /* through a DEREF destination — a different store arm, same rule */
  calls = 0; y = (*p = f());
  if (calls != 1 || y.a != 1 || y.b != 2 || x.a != 1 || x.b != 2) return 2;

  /* the plain statement form was always right; kept so a fix cannot trade it */
  calls = 0; x = f();
  if (calls != 1 || x.a != 1 || x.b != 2) return 3;

  /* three deep: the count grew with the chain (1 + n), so this is the shape
     that says whether the fix is per-node or per-chain */
  calls = 0; z = y = (x = f());
  if (calls != 1 || z.a != 1 || z.b != 2 || y.a != 1 || x.b != 2) return 4;

  /* as a call ARGUMENT, where the value is consumed rather than stored */
  calls = 0;
  { struct S t = (x = f()); if (calls != 1 || t.a != 1 || t.b != 2) return 5; }

  printf("ok\n");
  return 0;
}
