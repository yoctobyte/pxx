/* A multidim array reached through a STRUCT FIELD decays exactly as the same
   array reached through a bare identifier does. Both readers that answer
   "what does dereferencing this step by / load" — CDerefDecayStride and
   CNodePointeeTk's decayed-row arm — walked left to an AN_IDENT and gave up
   on an AN_FIELD, so the decay never happened: the deref stayed a LOAD, and
   the loaded element was then used as an address.

   Five of these SIGSEGV'd and one silently loaded four bytes of a char row
   (`*a.s[1]` came back 25699, the bytes 'c','d',0,0). Every line below is
   paired with the identical construct over a global, which was already right
   — the pairing is the point: no spelling of an array may answer differently
   from any other.
   refactor-c-one-array-shape-reader-instead-of-four-ident-field-pairs */
#include <string.h>

struct S {
  char s[3][8];
  int  m[3][4];
  int  t[2][3][4];
  double d[2][3];
};

struct S a;
char gs[3][8];
int  gm[3][4];
int  gt[2][3][4];
double gd[2][3];

int fails = 0;

static void chk(int got, int want) { if (got != want) fails++; }

int main(void) {
  int i, j, k;

  strcpy(a.s[0], "ab"); strcpy(a.s[1], "cd"); strcpy(a.s[2], "ef");
  strcpy(gs[0], "ab"); strcpy(gs[1], "cd"); strcpy(gs[2], "ef");
  for (i = 0; i < 3; i++) for (j = 0; j < 4; j++) { a.m[i][j] = i*10+j; gm[i][j] = i*10+j; }
  for (i = 0; i < 2; i++) for (j = 0; j < 3; j++) for (k = 0; k < 4; k++)
    { a.t[i][j][k] = i*100+j*10+k; gt[i][j][k] = i*100+j*10+k; }
  for (i = 0; i < 2; i++) for (j = 0; j < 3; j++)
    { a.d[i][j] = i*10+j; gd[i][j] = i*10+j; }

  /* double deref of a 2-D char array: both levels decay, the load is one byte */
  chk(**gs,  'a');
  chk(**a.s, 'a');          /* was: SIGSEGV */

  /* one subscript then a deref — the row is a char*, so a ONE-byte load */
  chk(*gs[1],  'c');
  chk(*a.s[1], 'c');        /* was: 25699 — four bytes of the row */

  /* pointer arithmetic over the outer dimension, then two derefs */
  chk(*(*(gm+1)+2),  12);
  chk(*(*(a.m+1)+2), 12);   /* was: SIGSEGV */

  /* 3-D: subscript first, then arithmetic on the remaining two levels */
  chk(*(*(gt[1]+2)+3),  123);
  chk(*(*(a.t[1]+2)+3), 123);   /* was: SIGSEGV */

  /* 3-D: arithmetic all the way down, no subscript anywhere */
  chk(*(*(*(gt+1)+2)+3),  123);
  chk(*(*(*(a.t+1)+2)+3), 123); /* was: SIGSEGV */

  /* the decayed row handed to a function expecting a char* */
  chk(strcmp(*(gs+1),  "cd"), 0);
  chk(strcmp(*(a.s+1), "cd"), 0);   /* was: SIGSEGV */

  /* an 8-byte element, so a wrong pointee width cannot pass by luck the way
     a char row can (a char row is 8 bytes here and so is a pointer) */
  chk((int)*(*(gd+1)+2),  12);
  chk((int)*(*(a.d+1)+2), 12);

  /* the row itself still measures and decays as a row */
  chk((int)sizeof(a.m[1]), 16);
  chk((int)sizeof(gm[1]),  16);
  chk((int)(*(a.m+1) - *(a.m+0)), 4);
  chk((int)(*(gm+1) - *(gm+0)), 4);

  /* ...and the difference of two ELEMENT addresses is in elements, not rows.
     &a.m[1][0]-&a.m[0][0] is 16 bytes apart over a 4-byte element = 4; asking
     the row stride instead divides 16 by 16 and answers 1, which is what
     IRArrayElemStride's missing field arm did.
     bug-a-irarrayelemstride-has-no-field-arm-so-it-answers-the-row-stride */
  chk((int)(&gm[1][0]  - &gm[0][0]),  4);
  chk((int)(&a.m[1][0] - &a.m[0][0]), 4);
  chk((int)(&gs[2][0]  - &gs[0][0]),  16);
  chk((int)(&a.s[2][0] - &a.s[0][0]), 16);
  chk((int)(&gd[1][0]  - &gd[0][0]),  3);
  chk((int)(&a.d[1][0] - &a.d[0][0]), 3);
  chk((int)(&gt[1][0][0]  - &gt[0][0][0]),  12);
  chk((int)(&a.t[1][0][0] - &a.t[0][0][0]), 12);

  return fails == 0 ? 42 : 1;
}
