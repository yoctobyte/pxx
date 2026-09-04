/* AN AGGREGATE THROUGH `...`, EVERY AAPCS64 CLASS, WITH A TRAILING INTEGER.
 *
 * The aarch64 third of
 * bug-a-c-the-variadic-struct-abi-is-still-a-pointer-on-aarch64-arm32-and-riscv32.
 * A struct in a variadic slot used to occupy one pointer-width slot holding the
 * address of a caller temp; clang and gcc put the aggregate's own bytes there.
 *
 * AND ON THIS TARGET THE VARIADIC RULE IS THE FIXED RULE, UNCHANGED — HFAs
 * INCLUDED. Measured against `clang --target=aarch64-linux-gnu -O1 -S`:
 * `{double,double}` past the named parameters still goes in d0,d1 on AArch64
 * Linux. That is worth saying because the opposite is the widely-read belief —
 * Apple's variant DOES drop HFA treatment in the tail, and Apple's is the
 * platform most of the written material describes. The other two targets on
 * that ticket are three different rules again, and two of them differ from
 * their own fixed-parameter rule; the table is on the ticket.
 *
 * Each call carries a LEADING scalar, so the bank is already partly spent when
 * the aggregate arrives, and a TRAILING integer, which is the only thing that
 * reports the bank state AFTER it. Sizes are in explicit widths because `long`
 * is 4 bytes on the 32-bit targets and a struct chosen for its 64-bit size is a
 * different shape there.
 *
 *   {int,int}        8  -> x1 packed,     tail w2
 *   {int,int,int}   12  -> x1, x2,        tail w3
 *   {double,double} 16  -> d0, d1,        tail w1   (HFA, and the tail moves)
 *   {int x6}        24  -> POINTER x1,    tail w2
 *
 * pxx now emits all four, register for register.
 *
 * BOTH HALVES MOVED IN ONE COMMIT AND THAT IS NOT TIDINESS. Measured while
 * writing this: with the caller converted and the receiving half still reading
 * one pointer slot, this file SEGFAULTS on aarch64. A caller and a callee that
 * disagree about what a slot CONTAINS do not produce a wrong value in one
 * argument, they produce a wrong everything after it.
 *
 * LIKE ITS SIBLING, THIS IS A REGRESSION GUARD AND NOT THE PROOF, and for the
 * same measured reason: caller and callee are both built by pxx, so before the
 * fix they agreed with each other and every value arrived intact. A pxx-vs-pxx
 * test cannot see a wrong calling convention. What proved it is the clang call
 * site read against pxx's own disassembly, row by row, recorded on the ticket.
 *
 * Wired on five targets. Only one is aarch64: the other four are the control
 * that a change to a SHARED crtl helper and a shared cparser arm did not
 * disturb them. Byte-identical to gcc on all five.
 */
#include <stdio.h>
#include <stdarg.h>
struct i2 { int a, b; };
struct i3 { int a, b, c; };
struct d2 { double x, y; };
struct i6 { int a,b,c,d,e,f; };
void v(int n, ...)
{
  va_list ap; va_start(ap, n);
  if (n == 1) { struct i2 s = va_arg(ap, struct i2); int t = va_arg(ap, int);
                printf("1 %d %d %d\n", s.a, s.b, t); }
  if (n == 2) { struct i3 s = va_arg(ap, struct i3); int t = va_arg(ap, int);
                printf("2 %d %d %d %d\n", s.a, s.b, s.c, t); }
  if (n == 3) { struct d2 s = va_arg(ap, struct d2); int t = va_arg(ap, int);
                printf("3 %.1f %.1f %d\n", s.x, s.y, t); }
  if (n == 4) { struct i6 s = va_arg(ap, struct i6); int t = va_arg(ap, int);
                printf("4 %d %d %d %d %d %d %d\n", s.a,s.b,s.c,s.d,s.e,s.f, t); }
  va_end(ap);
}
int main(void)
{
  struct i2 a; struct i3 b; struct d2 c; struct i6 d;
  a.a=1; a.b=2;
  b.a=3; b.b=4; b.c=5;
  c.x=1.5; c.y=2.5;
  d.a=6; d.b=7; d.c=8; d.d=9; d.e=10; d.f=11;
  v(1, a, 77); v(2, b, 77); v(3, c, 77); v(4, d, 77);
  return 0;
}
