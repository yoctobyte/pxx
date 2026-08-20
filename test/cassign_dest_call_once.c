/* An assignment destination is evaluated EXACTLY ONCE -- including when it is a
   CALL. `*f() = v` called f twice, for a scalar destination as well as a struct
   one, and the values it stored were correct every time: only the side effect
   doubled, which no output comparison catches.

   Two distinct mechanisms produced it, and both are pinned here:

     1. A DISCARDED assignment (a statement, or a comma's left operand). C's
        "an assignment is an expression yielding the stored value" rule appends
        a load-back, and the statement-level discard marked that load's ADDRESS
        operand as a statement to be emitted. The address IS the call, and the
        store already dragged it in -- so it was emitted twice.

     2. A CONSUMED assignment (`t = (*f() = 6)`). The IR is emitted by walking
        each statement root's operand tree with no value cache, so a node
        reachable from two roots runs twice: the store_mem is one root and
        whatever consumes the load-back is the other. Fixed by parking a
        call-bearing destination address in a pointer temp, which the store
        fills once and the loads read.

   The index and field destinations (`f()[0] = v`, `f()->m = v`) were always
   right, because there both consumers reference the index/field node instead
   of the call.

   Exit 0 on agreement; each check exits with its own number so a failure says
   which shape broke. Verified against gcc on the same source.
   bug-c-a-dereferenced-call-on-the-left-of-an-assignment-runs-twice */
#include <stdio.h>

struct S { long long a; long long b; };

static int calls;
static long long lbuf[8];
static struct S sbuf[4];

static long long *lbump(void) { calls++; return &lbuf[0]; }
static struct S *sbump(void)  { calls++; return &sbuf[0]; }

int main(void) {
  struct S v, w;
  long long t;

  v.a = 1; v.b = 2;

  /* scalar destination, discarded (statement) */
  calls = 0; *lbump() = 5;
  if (calls != 1 || lbuf[0] != 5) return 1;

  /* scalar destination, value consumed */
  calls = 0; t = (*lbump() = 6);
  if (calls != 1 || t != 6 || lbuf[0] != 6) return 2;

  /* struct destination, discarded */
  calls = 0; *sbump() = v;
  if (calls != 1 || sbuf[0].a != 1 || sbuf[0].b != 2) return 3;

  /* struct destination, value consumed */
  calls = 0; v.a = 3; w = (*sbump() = v);
  if (calls != 1 || w.a != 3 || sbuf[0].a != 3) return 4;

  /* the shapes that were already right, so a fix cannot regress them */
  calls = 0; lbump()[0] = 7;
  if (calls != 1 || lbuf[0] != 7) return 5;
  calls = 0; sbump()->a = 8;
  if (calls != 1 || sbuf[0].a != 8) return 6;

  /* a comma's left operand is discarded the same way a statement is */
  calls = 0; t = ((*lbump() = 9), 11);
  if (calls != 1 || t != 11 || lbuf[0] != 9) return 7;

  /* nested: the outer destination is a call too, and both must run once */
  calls = 0; *lbump() = (*lbump() = 12);
  if (calls != 2 || lbuf[0] != 12) return 8;

  /* a destination WITHOUT a side effect keeps its plain lowering */
  { long long *p = lbuf; t = (*p++ = 13);
    if (p - lbuf != 1 || t != 13 || lbuf[0] != 13) return 9; }

  printf("ok\n");
  return 0;
}
