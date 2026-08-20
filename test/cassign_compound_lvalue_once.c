/* `x OP= y` evaluates its lvalue EXACTLY ONCE. It evaluated it twice.

   cparser desugars a compound assignment to `x = x OP y` and REUSES the one
   lvalue AST node in both places -- the comment there said "since it is a pure
   lvalue read this is safe", which is the assumption C breaks. Lowering walked
   that node twice and ran its side effects twice: `*f() += 1` called f twice,
   `a[i++] += 1` stepped i twice, and `*p++ += 1` advanced p by TWO. The stored
   values were right every time, so only the side effect doubled -- the failure
   no output comparison catches. The increment operators never had it
   (AN_INCDEC lowers the address once), which is the model the fix follows: the
   destination address is lowered once and the shared node is pinned to it and
   to the value read through it for the duration of the RHS.

   The plain `=` half of the same family is cassign_dest_call_once.c.

   A plain-char lvalue is here on purpose: it arrives promoted, three binops
   deep (`((lv & 0xFF) ^ 0x80) - 0x80`), and kept its double evaluation after
   the direct spelling was already fixed.

   Exit 0 on agreement; each check exits with its own number so a failure says
   which shape broke. Verified against gcc on the same source.
   bug-c-a-compound-assignment-evaluates-its-lvalue-twice */
#include <stdio.h>

struct S { long long a; int b; };

static int calls, idxc;
static long long lbuf[8];
static int ibuf[8];
static double dbuf[4];
static char cbuf[8];
static struct S sbuf[2];

static long long *lbump(void) { calls++; return &lbuf[0]; }
static struct S *sbump(void)  { calls++; return &sbuf[0]; }
static int ibump(void) { idxc++; return 1; }

int main(void) {
  long long *p, *q, **pp;

  /* a call as the dereferenced lvalue */
  lbuf[0] = 1; calls = 0; *lbump() += 1;
  if (calls != 1 || lbuf[0] != 2) return 1;

  /* a call in the INDEX of the lvalue */
  lbuf[0] = 3; idxc = 0; lbuf[ibump() - 1] += 4;
  if (idxc != 1 || lbuf[0] != 7) return 2;

  /* a call producing the struct the field belongs to */
  sbuf[0].a = 7; calls = 0; sbump()->a *= 3;
  if (calls != 1 || sbuf[0].a != 21) return 3;

  /* an increment in the lvalue: the classic `*p++ += 1` */
  lbuf[0] = 5; lbuf[1] = 50; p = lbuf; *p++ += 1;
  if (p - lbuf != 1 || lbuf[0] != 6 || lbuf[1] != 50) return 4;

  /* ...and the index form of the same thing */
  { int i = 0; ibuf[0] = 8; ibuf[1] = 80; ibuf[i++] += 2;
    if (i != 1 || ibuf[0] != 10 || ibuf[1] != 80) return 5; }

  /* a FLOAT lvalue: the address node carries its element type, and storing it
     into the pointer temp must not run C's double->int conversion on it */
  dbuf[0] = 1.5; idxc = 0; dbuf[ibump() - 1] += 0.25;
  if (idxc != 1 || dbuf[0] != 1.75) return 6;

  /* a plain-char lvalue promotes on the way in */
  cbuf[0] = 'A'; idxc = 0; cbuf[ibump() - 1] += 2;
  if (idxc != 1 || cbuf[0] != 'C') return 7;

  /* POINTER arithmetic must still scale: this is what switching to the
     AN_COMPOUND_ASSIGN node would have broken (it read-modify-writes raw) */
  q = lbuf; pp = &q; *pp += 3;
  if (q - lbuf != 3) return 8;

  /* the value of a compound assignment is the stored value */
  lbuf[0] = 10; calls = 0;
  { long long v = (*lbump() += 5);
    if (calls != 1 || v != 15 || lbuf[0] != 15) return 9; }

  /* nested, both lvalues side-effecting */
  lbuf[0] = 1; ibuf[0] = 2; calls = 0; idxc = 0;
  *lbump() += (ibuf[ibump() - 1] += 4);
  if (calls != 1 || idxc != 1 || lbuf[0] != 7 || ibuf[0] != 6) return 10;

  /* the shift and bitwise forms take the same desugar */
  lbuf[0] = 1; calls = 0; *lbump() <<= 3;
  if (calls != 1 || lbuf[0] != 8) return 11;
  lbuf[0] = 0xF0; calls = 0; *lbump() &= 0x3C;
  if (calls != 1 || lbuf[0] != 0x30) return 12;

  /* an ordinary compound assignment keeps working (and keeps its IR) */
  { int t = 5; t += 3; t *= 2; ibuf[1] = 4; ibuf[1] -= 1;
    if (t != 16 || ibuf[1] != 3) return 13; }

  printf("ok\n");
  return 0;
}
