/* `(double)someFloat` was an AN_PTR_CAST retag: the node claimed tyDouble while
   the value was still four single bytes. Free on x86-64 and aarch64 -- their
   value model already carries a single as double bits in a register -- and
   wrong on arm32, riscv32 and i386, through exactly ONE consumer.

   Row 5 is that consumer and the only one that was red. Every other row
   converts on the way past (a store, a prototyped parameter, an arithmetic
   operand), so the lie never surfaced. Row 6 names the mechanism: the IMPLICIT
   form was always right, because default argument promotion sees a tySingle
   node and widens it -- the explicit cast HID the single from that promotion.

   Keep all eight. Dropping the rows that pass is what turns this back into the
   single mystery row it was filed as, and the file was mis-titled for exactly
   that reason: one failing shape named "a float parameter and return are wrong"
   when both are fine.
   bug-c-a-float-to-double-cast-is-a-retag-not-a-conversion */

#include <stdio.h>

int    as_int(double d) { return (int)(d * 100.0); }
double id_d(double d)   { return d; }

int main(void)
{
  float  r = 2.5f;
  double a = (double)r;
  double b = r;

  printf("1 %.2f\n", a);
  printf("2 %.2f\n", b);
  printf("3 %d\n",   as_int((double)r));
  printf("4 %d\n",   as_int(r));
  printf("5 %.2f\n", (double)r);
  printf("6 %.2f\n", r);
  printf("7 %.2f\n", (double)r * 2.0);
  printf("8 %.2f\n", id_d((double)r));

  /* The narrowing mirror, which must keep working and now composes with the
     widening: 16777217 is the smallest integer a float cannot represent, and
     0.1 printed to nine places is the single-precision tell.

     Row 11 reads a float VARIABLE deliberately. `(double)0.1f` -- the same value
     as a literal with the `f` suffix -- prints 0.100000000 here, because the
     suffix is ignored: that is a separate defect and the sibling of this one's
     own sibling, filed as bug-c-the-f-suffix-on-a-float-literal-is-ignored.
     Asserting it in THIS file would make one red stand for two mechanisms. */
  float tenth = 0.1f;
  printf("9 %.1f\n",  (double)(float)16777217.0);
  printf("10 %.1f\n", (double)(float)(double)(float)16777217.0);
  printf("11 %.9f\n", (double)tenth);
  return 0;
}
