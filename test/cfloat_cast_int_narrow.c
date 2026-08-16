/* `(float)i` in VALUE position must round the INTEGER to single precision.
   Sibling of cfloat_cast_narrow_b381: that one fixed the double->float value
   cast, this one the int->float value cast, which kept converting to a double
   and merely TAGGING the node tySingle. So `(double)(float)16777217` — the
   smallest integer a float cannot represent — answered 16777217 where C
   requires 16777216, while the identical value STORED into a float lvalue was
   right. gcc_diff_probe's int-to-float-casts case caught it on (float)4294967295u.

   The fix reuses b381's anonymous tySingle temp rather than adding a third
   conversion (normalise-dont-special-case).
   bug-c-cast-to-float-in-value-position-does-not-round-to-single */
static float sink;
static double rt(int a) { return (float)a; }
int main(void) {
    int i = 16777217;                 /* 2^24+1 */
    unsigned int u = 4294967295u;     /* rounds UP to 2^32 in a float */
    long long v = 16777217LL;
    unsigned long long uv = 16777217ULL;
    char c = 100;
    if ((double)(float)i != 16777216.0) return 1;
    if ((double)(float)u != 4294967296.0) return 2;
    if ((double)(float)v != 16777216.0) return 3;
    if ((double)(float)uv != 16777216.0) return 4;
    if (rt(i) != 16777216.0) return 5;
    /* the store path was always right and must stay right */
    sink = i;
    if ((double)sink != 16777216.0) return 6;
    /* argument/arithmetic position */
    if ((double)((float)i + (float)i) != 33554432.0) return 7;
    /* small values are exact and unchanged, and char/negatives survive */
    if ((double)(float)c != 100.0) return 8;
    if ((double)(float)(-5) != -5.0) return 9;
    /* a cast to DOUBLE must NOT narrow */
    if ((double)i != 16777217.0) return 10;
    if ((long double)i != 16777217.0L) return 11;
    /* (int) of the narrowed value */
    if ((int)(float)i != 16777216) return 12;
    return 42;
}
