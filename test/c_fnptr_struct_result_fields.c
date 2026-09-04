/* SPDX-License-Identifier: Zlib */
/* A STRUCT RETURNED BY VALUE THROUGH A FUNCTION POINTER, and the fields read
 * off the result.
 *
 * THE BUG THIS PINS WAS A SILENT WRONG VALUE, rc=0, no warning.
 * `struct P3 (*fp)(int) = mk3; fp(0).y` printed 7 where gcc prints 11 — and
 * `.z` printed 7 as well, because EVERY field resolved at offset 0.
 *
 * CParseFnSigGroup registers the Procs[] signature row for a function-pointer
 * type. It recorded the parameter record ids, and it recorded the pointed-at
 * record for a struct-POINTER return (`struct S *(*)()`, so that `p()->field`
 * works) — but not the record of a struct returned BY VALUE. ResolveNodeRec
 * reads ProcRetRecId[ASTIVal[node]] for every call kind, an indirect call
 * carries that signature's index there, and an unset field answers REC_NONE,
 * which applies the member at offset 0.
 *
 * A DIRECT call was always right: a named C function records the same thing at
 * the bottom of its declaration parser. So the defect needed BOTH a function
 * pointer AND a member read off the call result, which is why it survived —
 * assigning to a struct local first is correct, and that is how most code is
 * written. Row 2 and row 6 are those correct spellings, kept here so a future
 * change cannot "fix" row 5 by breaking the path everything else uses.
 *
 * ROWS 3, 4, 2 AND 6 ARE THE ARMS THAT MUST NOT BREAK, not padding: the
 * REC_NONE the bug produced is also what a too-eager fix produces if it starts
 * answering with the wrong record, and a test that only checked the broken
 * spelling would pass while direct calls regressed.
 *
 * WIDTH-INDEPENDENT ON PURPOSE. Every value here is chosen to print the same
 * on 32- and 64-bit, so this file can run on every cross target against ONE
 * expected transcript rather than needing a per-width oracle. `struct Mix`
 * still carries a `long` and a `double` so field ALIGNMENT differs between the
 * widths — that is the part worth exercising — but the value stored in the
 * long fits in 32 bits so the printed text does not. An earlier draft stored
 * 1234567890123 and the two widths disagreed by construction, which would have
 * made this a test about sizeof(long).
 *
 * bug-c-a-field-past-the-first-eight-bytes-of-an-indirect-call-s-struct-result-reads-back-as-offset-zero
 */
#include <stdio.h>

struct P3  { int x, y, z; };                  /* 12 bytes: z is past the first 8 */
struct P5  { int a, b, c, d, e; };            /* 20: fields past both return regs */
struct Mix { char c; int i; double d; long l; };
struct Big { int v[8]; };                     /* 32: memory class, sret */

static struct P3  mk3(int s){ struct P3 p; p.x=7+s; p.y=11; p.z=13; return p; }
static struct P5  mk5(int s){ struct P5 p; p.a=1+s; p.b=2; p.c=3; p.d=4; p.e=5; return p; }
static struct Mix mkm(int s){ struct Mix m; m.c='A'+s; m.i=99; m.d=2.5; m.l=123456789L; return m; }
static struct Big mkb(int s){ struct Big b; int i; for (i = 0; i < 8; i++) b.v[i] = i*10 + s; return b; }

typedef struct P3 (*F3)(int);

/* A function-TYPED parameter, the second CParseFnSigGroup call site. busybox
 * writes callbacks this way without a typedef, so it is not a curiosity. */
static int viaparam(struct P3 cb(int)) { return cb(0).z; }

int main(void)
{
  struct P3 (*f3)(int) = mk3;
  struct P5 (*f5)(int) = mk5;
  struct Mix(*fm)(int) = mkm;
  struct Big(*fb)(int) = mkb;
  F3 tf = mk3;

  /* 1: the bug — member read straight off an indirect call's struct result. */
  printf("1 %d %d %d\n", f3(0).x, f3(0).y, f3(0).z);
  /* 2: through a struct local (was always correct). */
  { struct P3 v = f3(0); printf("2 %d %d %d\n", v.x, v.y, v.z); }
  /* 3: DIRECT call, member off the result (was always correct). */
  printf("3 %d %d %d\n", mk3(0).x, mk3(0).y, mk3(0).z);
  /* 4: plain local, no call at all. */
  { struct P3 v; v.x = 7; v.y = 11; v.z = 13; printf("4 %d %d %d\n", v.x, v.y, v.z); }
  /* 5: the same through a TYPEDEF'd function-pointer type. */
  printf("5 %d %d %d\n", tf(0).x, tf(0).y, tf(0).z);
  /* 6: a single member on its own, outside any argument list — the bug was not
        an argument-list interaction, and a row that only tested printf's
        variadic path would have said it was. */
  { int y = f3(0).y; printf("6 %d\n", y); }
  /* 7: five ints, fields past both return registers. */
  printf("7 %d %d %d %d %d\n", f5(0).a, f5(0).b, f5(0).c, f5(0).d, f5(0).e);
  /* 8: mixed widths — alignment differs between 32- and 64-bit here. */
  printf("8 %c %d %.1f %ld\n", fm(0).c, fm(0).i, fm(0).d, fm(0).l);
  /* 9: 32 bytes, returned in memory (sret) rather than in registers. */
  printf("9 %d %d %d %d\n", fb(0).v[0], fb(0).v[3], fb(0).v[6], fb(0).v[7]);
  /* 10: a function-typed PARAMETER, the other signature call site. */
  printf("10 %d\n", viaparam(mk3));
  /* 11: two different indirect calls in one argument list. */
  printf("11 %d %d %d %d\n", f3(0).x, f5(0).e, f3(0).z, f5(0).a);
  return 0;
}
