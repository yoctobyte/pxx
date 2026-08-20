/* The DESTINATION half of the rule cstruct_assign_value_side_effects.c pins
   for the source: a struct assignment must evaluate its LEFT-hand side exactly
   ONCE.

   It evaluated it twice. Making the assignment yield the stored value (the C
   rule the sibling test is about) was done by lowering the LHS a SECOND time
   for the result — which re-emits the LHS's side effects, so `*p++ = v`
   advanced p by two, `buf[i++] = v` incremented i twice, and `*f() = v` called
   f twice. Fixed by reusing the destination operand the copy already carries;
   the scalar arms had always done it that way.

   Found through quickjs, whose interpreter pushes with `*sp++ = <JSValue>` on
   every opcode: `1+2` evaluated to 2 and every literal to 0, because the stack
   pointer ran ahead of the values. Values were plausible and wrong, never a
   crash at the cause.
   bug-c-quickjs-runner-segfaults-with-zero-output-on-the-full-smoke-js

   Exit 0 on agreement; each check exits with its own number so a failure says
   which shape broke. Verified against gcc on the same source. */
#include <stdio.h>

struct S { long long a; long long b; };
struct S4 { int x; };

static struct S buf[8];
static struct S4 buf4[8];

int main(void) {
  struct S v, *p;
  struct S4 w, *q;
  int i;

  v.a = 9; v.b = 99;
  w.x = 7;

  /* post-increment: the quickjs `*sp++ = value` shape, 16-byte struct */
  p = buf; *p++ = v;
  if (p - buf != 1 || buf[0].a != 9 || buf[0].b != 99) return 1;

  /* ...and twice in a row, so a doubled step lands in the wrong slot too */
  p = buf; buf[1].a = 0; v.a = 1; *p++ = v; v.a = 2; *p++ = v;
  if (p - buf != 2 || buf[0].a != 1 || buf[1].a != 2) return 2;

  /* pre-increment */
  v.a = 3; p = buf; *++p = v;
  if (p - buf != 1 || buf[1].a != 3) return 3;

  /* a struct SMALLER than a pointer takes the same path */
  q = buf4; *q++ = w; w.x = 8; *q++ = w;
  if (q - buf4 != 2 || buf4[0].x != 7 || buf4[1].x != 8) return 4;

  /* an index expression with a side effect */
  i = 0; v.a = 4; buf[i++] = v;
  if (i != 1 || buf[0].a != 4) return 5;

  /* post-decrement, so a doubled step is visible in the other direction */
  p = buf + 3; v.a = 5; *p-- = v;
  if (buf + 3 - p != 1 || buf[3].a != 5) return 6;

  /* the value of the assignment is still the destination — the rule the
     doubled lowering was introduced to satisfy. It must survive the fix. */
  i = 0; v.a = 6;
  { struct S t = (buf[i++] = v);
    if (i != 1 || t.a != 6 || buf[0].a != 6) return 7; }

  /* chained, through a destination that steps */
  p = buf; v.a = 8;
  { struct S t = (*p++ = v);
    if (p - buf != 1 || t.a != 8 || buf[0].a != 8) return 8; }

  printf("ok\n");
  return 0;
}
