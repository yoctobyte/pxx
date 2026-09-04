/* AN 8-BYTE-ALIGNED VARIADIC SLOT STARTS ON AN EVEN REGISTER.
 *
 * The riscv32 third of
 * bug-a-c-the-variadic-struct-abi-is-still-a-pointer-on-aarch64-arm32-and-riscv32,
 * and the half of it that is NOT about aggregates at all. riscv32 applied no
 * slot alignment anywhere in the variadic tail: measured against
 * `clang --target=riscv32-unknown-linux-gnu -O1 -S`, `v(1, 2.5, 77)` puts the
 * double in a2:a3 and the 77 in a4 — pxx packed the double into a1:a2 and put
 * the 77 in a3. Wrong for a `double`, an `int64` and an 8-byte-ALIGNED record
 * alike, which is why the fix reads the alignment from one oracle instead of
 * asking whether the argument happens to be 64-bit.
 *
 * Every row here has an ODD number of words ahead of the argument under test —
 * `n` alone — so a target that aligns and a target that packs put the value in
 * different registers. Row 6 is the control: an extra leading int makes the
 * sequence already even, so alignment changes nothing and the row must pass
 * either way. Without row 6 a harness that simply lost the padding everywhere
 * would still look consistent.
 *
 * A TRAILING INTEGER ON EVERY ROW. The padding word is invisible in the value
 * that comes back — a walker that skips it and a walker that does not both
 * return the same double — so the only thing that reports the slot sequence
 * AFTER the argument is what lands in the next one.
 *
 * REGRESSION GUARD, NOT THE PROOF, for the reason its siblings state: caller
 * and callee are both pxx, so a wrong convention is invisible to any outcome
 * this file can print. The proof is the clang call site against pxx's own
 * disassembly, on the ticket. What this file is able to catch is the two halves
 * drifting apart later, which is the thing that actually happens.
 *
 * Wired on five targets. Four of them already aligned correctly and are the
 * control that a shared cparser arm and a shared crtl walker did not move.
 */
#include <stdio.h>
#include <stdarg.h>
struct d1 { double d; };
struct l1 { long long x; };
struct i2 { int a, b; };
void v(int n, ...)
{
  va_list ap; va_start(ap, n);
  if (n == 1) { struct d1 s = va_arg(ap, struct d1); int t = va_arg(ap, int);
                printf("1 %.1f %d\n", s.d, t); }
  if (n == 2) { struct l1 s = va_arg(ap, struct l1); int t = va_arg(ap, int);
                printf("2 %lld %d\n", s.x, t); }
  if (n == 3) { struct i2 s = va_arg(ap, struct i2); int t = va_arg(ap, int);
                printf("3 %d %d %d\n", s.a, s.b, t); }
  if (n == 4) { double d = va_arg(ap, double); int t = va_arg(ap, int);
                printf("4 %.1f %d\n", d, t); }
  if (n == 5) { long long x = va_arg(ap, long long); int t = va_arg(ap, int);
                printf("5 %lld %d\n", x, t); }
  if (n == 6) { int a = va_arg(ap, int); double d = va_arg(ap, double);
                int t = va_arg(ap, int);
                printf("6 %d %.1f %d\n", a, d, t); }
  va_end(ap);
}
int main(void)
{
  struct d1 a; struct l1 b; struct i2 c;
  a.d = 1.5;
  b.x = 1234567890123LL;
  c.a = 8; c.b = 9;
  v(1, a, 77);
  v(2, b, 77);
  v(3, c, 77);
  v(4, 2.5, 77);
  v(5, 9876543210LL, 77);
  v(6, 4, 3.5, 77);
  return 0;
}
