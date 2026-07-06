/* Float-literal decode precision: StrToDoubleBits must round-to-nearest-even
 * (it used to truncate the mantissa, leaving every inexact literal 1 ulp low)
 * and must not decay large negative exponents (1.0e-100 formerly decoded to 0:
 * the scaling loop shed a whole decimal digit of N per step once D capped).
 * Broke sqlite's Dekker double-double kernels (AtoF/FpDecode), which depend on
 * exactly-decoded compensation constants: ROUND(2.5,0) gave 2.0, ROUND(75.125,2)
 * gave 75.12. Expected bit patterns are the correctly rounded IEEE 754 doubles
 * (gcc-verified). */
typedef unsigned long long u64;

static int chk(double v, u64 want) {
  union { double d; u64 u; } x;
  x.d = v;
  return x.u == want;
}

int main(void) {
  if (!chk(0.1,                          0x3fb999999999999aULL)) return 1;
  if (!chk(1.0e-01,                      0x3fb999999999999aULL)) return 2;
  if (!chk(1.0e-100,                     0x2b2bff2ee48e0530ULL)) return 3;
  if (!chk(1.0e+100,                     0x54b249ad2594c37dULL)) return 4;
  if (!chk(1.0e+300,                     0x7e37e43c8800759cULL)) return 5;
  /* sqlite dekkerMul2 compensation constants */
  if (!chk(5.5511151231257827021e-18,    0x3c5999999999999aULL)) return 6;
  if (!chk(1.5902891109759918046e+83,    0x5134f4d87b3b31f4ULL)) return 7;
  if (!chk(1.99918998026028836196e-117,  0x27b42a68781d46c4ULL)) return 8;
  if (!chk(3.6432197315497741579e-27,    0x3a720a5465df8d2cULL)) return 9;
  /* boundaries: max double, min normal */
  if (!chk(1.7976931348623157e308,       0x7fefffffffffffffULL)) return 10;
  if (!chk(2.2250738585072014e-308,      0x0010000000000000ULL)) return 11;
  /* mantissa-carry on rounding (all-ones mantissa rounds up into exponent) */
  if (!chk(9007199254740993.0,           0x4340000000000000ULL)) return 12; /* 2^53+1 -> 2^53 (even) */
  return 42;
}
