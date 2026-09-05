/* A pointer to a TYPEDEF'D array must describe the POINTEE, not the variable.

   `typedef double TA[4]; TA *p;` is a pointer to an array of four doubles.
   pxx entered the fixed-array declarator path on the typedef's inherent
   dimension alone, with no test on pointer depth, and stamped the [4] onto `p`
   itself — so `p` was an array of four pointers and `(*p)[i] = v` strided as
   though `p` were the array, writing off the object.

   The byte-equivalent `double (*p)[4]` was correct throughout, because that
   spelling is PARENTHESISED: ParseCDeclType consumes the whole declarator and
   it lands in the pointer-to-array arm, which records the length as the
   pointee's. Two spellings of one type that never met.

   BOTH ARMS ARE HERE, and they failed DIFFERENTLY, which is why neither alone
   would do. Measured at 10492cae86d8 (the fix stashed out), against gcc:

     local  `TA *p`   inside a function   -> SEGFAULT (rc=139)
     global `TA *gp`  at file scope       -> "0.00 0.00", rc=0, SILENT
     both direct spellings                -> correct, both compilers

   The global arm is the one busybox-shaped code reaches, and it is the one
   that says nothing. `devdocs/dev/normalise-dont-special-case.md` is about
   exactly this pair: fixing the arm whose failure is loud and leaving the arm
   whose failure is silent.

   ROWS 5-8 ARE NOT DECORATION. The guard added to both arms suppresses the
   inherent-dimension fold when the declarator has stars, so every use of that
   fold WITHOUT stars has to keep working, and `TA gs[2]` -> [2][4] is the one
   that would break first. They are the control on the guard, not on the bug.

   NOT ASSERTED HERE: `sizeof(TA)` — the TYPE NAME as operand — answers the
   element size (8 for this typedef, against gcc's 32). Measured on this file's
   own earlier draft and ablated to be PRE-EXISTING, not a regression from this
   fix; filed as bug-c-sizeof-of-an-array-typedef-name-answers-the-element-size.
   Left out deliberately rather than left in as a known-red row.

   bug-c-a-pointer-to-a-typedefd-array-segfaults-while-the-direct-spelling-works */

extern int printf(const char *, ...);

typedef double TA[4];

TA  ga;              /* the pointee, at file scope */
TA *gp;              /* the typedef'd spelling, global arm */
double  gb[4];
double (*gq)[4];     /* the direct spelling, global arm */

TA  gs[2];           /* inherent dim must still fold UNDER a declarator dim */
TA  gplain;          /* ...and must still apply on its own */

int main(void) {
  TA  la;
  TA *lp = &la;             /* typedef'd spelling, local arm — used to SEGFAULT */
  double  lb[4];
  double (*lq)[4] = &lb;    /* direct spelling, local arm */
  TA  lplain;
  int i;

  for (i = 0; i < 4; i++) (*lp)[i] = (i + 1) * 1.5;
  printf("1 %.2f %.2f\n", la[0], la[3]);

  for (i = 0; i < 4; i++) (*lq)[i] = (i + 1) * 1.5;
  printf("2 %.2f %.2f\n", lb[0], lb[3]);

  gp = &ga;
  for (i = 0; i < 4; i++) (*gp)[i] = (i + 1) * 1.5;
  printf("3 %.2f %.2f\n", ga[0], ga[3]);

  gq = &gb;
  for (i = 0; i < 4; i++) (*gq)[i] = (i + 1) * 1.5;
  printf("4 %.2f %.2f\n", gb[0], gb[3]);

  /* 5-8: the fold the guard must NOT have suppressed. */
  for (i = 0; i < 4; i++) { gplain[i] = i + 1; lplain[i] = i + 10; }
  gs[0][0] = 7; gs[1][3] = 9;
  printf("5 %d %d\n", (int)sizeof(gplain), (int)sizeof(gs));
  printf("6 %.0f %.0f\n", gplain[0], gplain[3]);
  printf("7 %.0f %.0f\n", lplain[0], lplain[3]);
  printf("8 %.0f %.0f\n", gs[0][0], gs[1][3]);
  return 0;
}
