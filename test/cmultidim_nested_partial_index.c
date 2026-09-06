/* Regression, the PARTIAL face of bug-c-multidim-nested-subscript.

   test/cmultidim_nested_index_subscript.c covers the FULL-index face: a nested
   multi-dim read used as a subscript re-enters the flatten and clobbers
   NDIdxNode[] and NDInfo*, giving a wrong ELEMENT of the right array. Both of
   its subject lines are full-index at rank 2, so nothing in that file ever
   decays to a pointer and the partial face is absent rather than thin.

   A PARTIAL index -- fewer subscripts than the rank -- decays to a pointer, and
   its trailing stride is computed from NDInfoSpan[] AFTER the subscript loop.
   That is a different read of the same clobbered globals, and it fails
   differently: not a wrong value, a wrong ADDRESS. With the two re-primes in
   cparser.inc's flatten removed, rows A, B and D print wrong values and row C
   SEGFAULTS.

   THESE ROWS EXIST TO SEPARATE TWO CANDIDATE REPAIRS, which is the reason not
   to trim them. A fix that copies only the RANK locally passes A, B and D and
   still computes C's trailing stride from the inner array's spans. frankH
   measured exactly this on the Pascal side (a92a26917) and reached for the
   rank-only shape first; so did I, independently. Row C is the only one that
   tells them apart.

   TWO WAYS THIS FIXTURE COULD HAVE BEEN A GUARD THAT CANNOT FAIL. Both were
   measured against a compiler with the re-primes removed, not reasoned about:

   1. EVERY NESTED INDEX HERE IS ITSELF MULTI-DIM. The shape resolver refuses
      rank 1 and CLEARS, so a nested 1-D read clobbers nothing. A probe built
      from one reports this whole class as clean while being perfectly correct
      about a case the bug cannot reach.

   2. DO NOT "SIMPLIFY" ROW C's `z3[1][ z2[1][1] ]` TO `z3[ z2[1][1] ]`. A
      partial index with ONE subscript is immune by construction: it never
      enters the `while (tkLBrack)` loop, and cparser resolves the array's shape
      AFTER parsing the first index (cparser.inc:4770 parses, then 4772
      resolves), so the globals are re-filled for the right array whether or not
      the loop re-primes. That row passes on a deliberately broken compiler and
      is indistinguishable from real coverage. Row C needs two subscripts with
      the nested read in a position the LOOP parses.

   Output is compared against gcc's, so no expected value is transcribed here or
   in the Makefile and a row added later needs none re-derived. */

#include <stdio.h>

int z3[3][3][3];
int z2[2][2];

int main(void) {
    int i, j, k;
    int *q;

    for (i = 0; i < 3; i++)
        for (j = 0; j < 3; j++)
            for (k = 0; k < 3; k++)
                z3[i][j][k] = 100*i + 10*j + k;

    z2[0][0] = 0; z2[0][1] = 2;
    z2[1][0] = 1; z2[1][1] = 2;

    /* A: nested read in a MIDDLE position of a rank-3 full index. The subscript
          count is checked against whatever rank the globals hold, which is why
          the Pascal side REFUSED this shape outright rather than mis-reading. */
    printf("A %d\n", z3[1][ z2[0][1] ][2]);

    /* B: nested read LAST. Compiles either way; a clobbered NDIdxNode[] yields
          a different element of the right array. */
    printf("B %d\n", z3[1][2][ z2[1][0] ]);

    /* C: THE PARTIAL ROW, and the one that discriminates. Two subscripts on a
          rank-3 array decays to int*, and the trailing stride comes from the
          spans left in the globals after the loop. */
    q = z3[1][ z2[1][1] ];
    printf("C %d %d\n", q[0], q[2]);

    /* D: two levels of nesting -- the save cannot be a single global slot. */
    printf("D %d\n", z3[1][ z2[ z2[0][0] ][1] ][0]);

    /* E: the inner array still reads correctly afterwards. */
    printf("E %d\n", z2[1][1]);

    /* A terminal line, so a run that dies partway through cannot pass by
       producing a prefix of the right output. */
    printf("MULTIDIM NESTED PARTIAL OK\n");
    return 0;
}
