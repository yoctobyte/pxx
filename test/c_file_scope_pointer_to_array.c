/* A file-scope `int (*gp)[4]` recorded NO pointee: ParseCGlobalVarDecl had zero
   SymPtrElem* writes where ParseCLocalDeclAST and ParseCSubroutine both have
   them, so `sizeof(*gp)` answered the ELEMENT size (4) and `gp[i][j]` indexed
   with a 4-byte stride instead of 16 -- a wrong address, not a crash, except
   where it walked off the object. The same declaration also never bound its
   initializer: the branch's scalar `= expr` arm knew function names only, so
   `= gm` was token-skipped and the pointer stayed nil.

   Every assertion here is DERIVED, never a constant. A size row that spells
   out `16` passes just as well when the compiler substituted a plausible
   default, and one that spells out `8` cannot be told from sizeof(void*)
   arriving by accident. So the size is checked against the MEASURED stride
   (&gp[1] - &gp[0]) and against the real array it points into (sizeof(gm[0])),
   and the index rows read back a value written through the array name. The
   local `lp` rows are the positive control: they took the working path all
   along, so a run in which they too fail is the harness misfiring, not this
   defect. */
#include <stdio.h>

int gm[3][4];
int ga[4];
int (*gp)[4]  = gm;    /* pointer-to-array <- 2d array name */
int (*gq)[4]  = &ga;   /* pointer-to-array <- &1d array     */
int *gplain   = ga;    /* control: plain pointer, always worked */

int main(void) {
  int lm[3][4];
  int (*lp)[4] = lm;
  long gstride = (char *)(gp + 1) - (char *)gp;
  long lstride = (char *)(lp + 1) - (char *)lp;
  int fails = 0;

  gm[2][3] = 77;
  lm[2][3] = 23;

  /* the initializers bound at all */
  if (gp != gm)      { printf("FAIL gp unbound\n"); fails++; }
  if (gq != &ga)     { printf("FAIL gq unbound\n"); fails++; }
  if (gplain != ga)  { printf("FAIL gplain unbound\n"); fails++; }

  /* size agrees with the stride the compiler actually emits */
  if ((long)sizeof(*gp) != gstride)
    { printf("FAIL global size %ld vs stride %ld\n", (long)sizeof(*gp), gstride); fails++; }
  if ((long)sizeof(*lp) != lstride)
    { printf("FAIL local size %ld vs stride %ld\n", (long)sizeof(*lp), lstride); fails++; }

  /* and with the array actually pointed into */
  if (sizeof(*gp) != sizeof(gm[0]))
    { printf("FAIL global size %ld vs row %ld\n",
             (long)sizeof(*gp), (long)sizeof(gm[0])); fails++; }
  if (sizeof(*gp) != sizeof(*lp))
    { printf("FAIL scopes disagree: %ld vs %ld\n",
             (long)sizeof(*gp), (long)sizeof(*lp)); fails++; }

  /* the stride is used, not merely recorded */
  if (gp[2][3] != 77) { printf("FAIL gp[2][3] = %d\n", gp[2][3]); fails++; }
  if (lp[2][3] != 23) { printf("FAIL lp[2][3] = %d\n", lp[2][3]); fails++; }

  if (fails == 0) printf("PTRARR OK stride=%ld\n", gstride);
  return fails;
}
