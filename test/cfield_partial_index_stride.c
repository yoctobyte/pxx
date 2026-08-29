/* A PARTIAL index of a multidim struct FIELD decays to a row pointer, and both
   halves of that were wrong — silently, with no test covering the shape at all.

   1. The decayed pointer carried no stride stamp, so IRPointerStride fell to its
      size-1 default and `*(s.m[1] + 1)` stepped ONE BYTE: 184549376 (11 shl 24)
      instead of 11. Exactly bug-c-a-decayed-array-row-steps-one-byte, which
      fixed the ARRAY arm and never reached the field arm.

   2. The offset multiplier was RecFieldRowStride — the OUTER row — whatever the
      partial index's depth. `int *q = s.m[1][2]` on `int m[2][3][4]` scaled by
      48 instead of 16, so the address left the object entirely and q[0] read
      whatever was next in memory.

   The bare-array spellings of both are here beside them: those arms were always
   right, and it is their being right that says these are defects rather than a
   pxx dialect choice. Oracle is gcc.
   bug-c-a-struct-field-partial-index-uses-the-outer-row-stride */
#include <stdio.h>

struct S2 { int m[3][4]; };
struct S3 { int m[2][3][4]; };

int main(void) {
  struct S2 s2; struct S3 s3;
  int a2[3][4], a3[2][3][4];
  int i, j, k;

  for (i = 0; i < 3; i++) for (j = 0; j < 4; j++) { s2.m[i][j] = i*10 + j; a2[i][j] = i*10 + j; }
  for (i = 0; i < 2; i++) for (j = 0; j < 3; j++) for (k = 0; k < 4; k++)
    { s3.m[i][j][k] = i*100 + j*10 + k; a3[i][j][k] = i*100 + j*10 + k; }

  /* (1) the row pointer's own stride */
  printf("f2 *(m[1]+1)=%d  a2 *(m[1]+1)=%d\n", *(s2.m[1] + 1), *(a2[1] + 1));
  printf("f2 *(m[2]+3)=%d  a2 *(m[2]+3)=%d\n", *(s2.m[2] + 3), *(a2[2] + 3));

  /* ...and through a named pointer, which took a different path and always worked */
  { int *r = s2.m[1]; printf("f2 r[0]=%d r[1]=%d\n", r[0], r[1]); }

  /* (2) partial index deeper than one subscript */
  { int *q = s3.m[1][2]; int *qa = a3[1][2];
    printf("f3 q[0]=%d q[3]=%d  a3 q[0]=%d q[3]=%d\n", q[0], q[3], qa[0], qa[3]); }

  /* one subscript of three -> int(*)[4], and the full index for control */
  { int (*p)[4] = s3.m[1]; printf("f3 p[0][0]=%d p[1][2]=%d full=%d\n",
                                  p[0][0], p[1][2], s3.m[1][2][3]); }
  return 0;
}
