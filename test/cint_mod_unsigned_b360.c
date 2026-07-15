/* Regression: C usual arithmetic conversions for integer `/` and `%`.
   `int op unsigned int` (equal rank, one unsigned) converts the signed operand to
   unsigned, so the operation is UNSIGNED. pxx keyed div/mod signedness on the LEFT
   operand alone, so `-13 % 61u` did a SIGNED modulo (-13) instead of the unsigned
   `(unsigned)-13 % 61`. (bug-c-int-mod-unsigned-uses-signed-conversion; also the
   residual of gcc-torture bitfld-1.c.)

   -13 as unsigned = 4294967283; 4294967283 % 61 == 44; 4294967283 / 61 == 70409299. */
int main(void) {
  int i = -13;
  unsigned u = 61;

  if ((unsigned)(i % u) != 44u)        return 1;   /* int % unsigned -> unsigned */
  if ((unsigned)(i / u) != 70409299u)  return 2;   /* int / unsigned -> unsigned */
  if ((unsigned)(-13 % 61u) != 44u)    return 3;   /* literal form */
  if ((unsigned)(u % i) != 61u)        return 4;   /* unsigned % int (61 % huge = 61) */

  /* signed % signed stays signed */
  if ((-13 % 61) != -13)               return 5;
  /* unsigned % unsigned unchanged */
  if ((4294967283u % 61u) != 44u)      return 6;
  return 42;
}
