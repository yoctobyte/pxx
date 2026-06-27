/* The result of integer arithmetic on unsigned operands must keep its unsigned
   type so a following relational compare uses an UNSIGNED comparison. Before,
   an inline `i - 1u` was tagged signed (CBinResultTk dropped unsignedness), so
   `(i - 1u) < asize` compiled to a SIGNED compare: with i==0 the wrapped
   0xFFFFFFFF read as -1 and `-1 < asize` was wrongly true. This is lua's
   `findindex` array-bounds test `i - 1u < asize`, which looped `pairs` forever. */

extern long __pxx_write(int, const void *, unsigned long);

int main(void) {
  unsigned int i = 0;
  unsigned int asize = 3;

  /* the lua findindex idiom: 0xFFFFFFFF < 3 must be FALSE (unsigned) */
  if ((i - 1u) < asize) return 1;
  if (!((i - 1u) > asize)) return 2;        /* 0xFFFFFFFF > 3 is true */

  /* a real in-range index still compares normally */
  i = 2;
  if (!((i - 1u) < asize)) return 3;        /* 1 < 3 */

  /* the subtraction result drives the compare against an unsigned var:
     (0u - 1u) wraps high, so > a small unsigned bound */
  {
    unsigned int z = 0, hundred = 100;
    if (!((z - 1u) > hundred)) return 4;     /* 0xFFFFFFFF > 100 unsigned */
  }

  /* unsigned <= compare on a subtraction result that wraps */
  {
    unsigned int n = 5, five = 5;
    if ((n - 10u) <= five) return 5;         /* wraps high -> NOT <= 5 */
  }
  return 42;
}
