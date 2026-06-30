/* C unsigned int (32-bit) arithmetic must wrap modulo 2^32 and compare unsigned,
   even when the expression is INLINE (not first stored into an unsigned var).
   pxx evaluated in 64-bit registers without truncation and compared signed, so
   each check below used to be wrong. Returns 42 iff all six match C semantics. */
int main(void)
{
  int ok = 0;
  unsigned int a = 5;
  if ((a - 10) > 0)            ok++;   /* 0xFFFFFFFB > 0 -> 1 */
  if ((5u - 10) > 0)           ok++;   /* u-suffix literal -> unsigned -> 1 */
  if ((0u - 1) > 1000)         ok++;   /* 4294967295 > 1000 -> 1 */
  if (!(-1 < 1u))              ok++;   /* unsigned cmp: !(false) -> 1 */
  if ((0u - 1) == 4294967295u) ok++;   /* exact wrap value */
  if ((10u - 5) == 5)          ok++;   /* normal (no wrap) */
  if (ok == 6) return 42;
  return ok;
}
