/* b232 (bug-c-duktape-double-formatting / NaN): IEEE unordered compare. The
   x86-64 float compare emitted ucomisd + plain setcc, reading only ZF/CF and
   ignoring PF (parity = unordered). On NaN, ucomisd sets ZF=PF=CF=1, so
   sete/setb/setbe reported 1 and setne reported 0 — i.e. NaN==NaN true,
   NaN!=NaN false, NaN<x true. That broke duktape's DUK_ISNAN (`x!=x`): String(0/0)
   printed INT_MIN instead of "NaN". Every ordered relation must be FALSE for NaN,
   and != must be TRUE. Fold in PF for ==,!=,<,<=. Exit 42 = pass. */
int main(void) {
    volatile double z = 0.0;
    double nan = z / z;        /* fff8000000000000 */
    double one = 1.0;
    if (nan == nan) return 1;  /* must be false */
    if (!(nan != nan)) return 2;  /* must be true */
    if (nan < one)  return 3;
    if (nan <= one) return 4;
    if (nan > one)  return 5;
    if (nan >= one) return 6;
    if (one < nan)  return 7;
    if (one > nan)  return 8;
    /* ordered comparisons still correct */
    if (!(one > 0.5)) return 9;
    if (!(0.5 < one)) return 10;
    if (!(one == 1.0)) return 11;
    if (!(one <= 1.0)) return 12;
    if (!(one >= 1.0)) return 13;
    return 42;
}
