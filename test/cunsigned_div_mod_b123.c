/* C unsigned int (32-bit) division/mod must be UNSIGNED on every target. The
   32-bit backends (i386/arm32/riscv32) used to emit signed idiv/sdiv/div, so a
   dividend with bit 31 set (>= 2^31) divided as a negative number. Returns 42
   iff all four checks match C semantics. */
int main(void)
{
  int ok = 0;
  unsigned int a = 3000000000u;   /* > 2^31, bit 31 set */
  unsigned int b = 7;
  if ((a / b) == 428571428u) ok++;   /* stored-operand divide */
  if ((a % b) == 4u)         ok++;
  if ((a / 7u) == 428571428u) ok++;  /* inline divide */
  if ((a % 7u) == 4u)        ok++;
  if (ok == 4) return 42;
  return ok;
}
