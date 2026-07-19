/* (float) cast of a double VALUE must narrow to single precision even when
   immediately widened back (C 6.3.1.5) — b381. The reinterpret/retag cast
   path made `(double)(float)d` a silent no-op: quickjs Math.fround(1.1)
   returned 1.1 instead of 1.100000023841858. The fix round-trips the value
   through an anonymous single-precision temp (store narrows, reload widens,
   on every backend). */
static double fr(double a) { return (float)a; }
static float g_f;
int main(void) {
    double x = 1.1;
    double direct = (double)(float)x;
    double viafn = fr(x);
    float fv = (float)x;
    double sum;
    g_f = (float)(x + 1.0);
    /* 1.1f == 0x3F8CCCCD == 1.10000002384185791015625 */
    if (!(direct > 1.10000002 && direct < 1.10000003)) return 1;
    if (direct != viafn) return 2;
    if ((double)fv != direct) return 3;
    if (!((double)g_f > 2.09999990 && (double)g_f < 2.10000010)) return 4;
    /* argument position */
    sum = (float)x + (float)x;
    if (sum != direct + direct) return 5;
    /* (float) of a float stays identity; int paths untouched */
    if ((float)fv != fv) return 6;
    if ((int)(float)2.9 != 2) return 7;
    return 42;
}
