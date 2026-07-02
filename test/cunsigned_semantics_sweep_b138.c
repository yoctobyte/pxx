/* feature-c-unsigned-semantics-suite-resweep: a matrix of unsigned-semantics
   hypotheses (right shift, narrow-type widening/truncation, mixed-width
   arithmetic, unsigned comparison, large literal typing, unsigned wraparound
   in a loop) verified against a real gcc oracle. Every check here already
   matched gcc when this was written -- this file's job is to PIN that going
   forward, not to demonstrate a fix (the one confirmed gap the parent ticket
   flagged, signed `>>`, has its own ticket/test:
   bug-c-signed-arith-shift-right / csigned_arith_shift_right_b137.c).
   No stdio dependency (cross-target friendly: this compiler's C variadic
   call path has pre-existing cross-target gaps unrelated to unsigned
   semantics) -- pure exit-code oracle, bitmask style like
   cunsigned_int_arith_b121.c. Returns 42 iff every check matches gcc. */
int main(void)
{
  int ok = 0;

  /* logical >> of unsigned (paired with the arithmetic >> of signed, which
     has its own dedicated ticket/test) */
  unsigned int v = 0x80000000u;
  if ((v >> 1) == 0x40000000u) ok++;                          /* 1 */

  /* unsigned char / unsigned short: C integer promotion to int, but the
     VALUE must stay in its declared range (zero-extended on load) */
  unsigned char c = 200;
  if ((c * 2) == 400) ok++;                                   /* 2 */
  unsigned char d = (unsigned char)300;
  if (d == 44) ok++;                                          /* 3 */
  unsigned short s = 60000;
  if ((s + 10000) == 70000) ok++;                             /* 4 */

  /* mixed-width unsigned arithmetic (tyUInt64 vs tyUInt32) */
  unsigned long ul = 5;
  unsigned int ui = 3;
  if ((ul * ui) == 15) ok++;                                  /* 5 */

  /* unsigned comparison after a cast */
  int sv = -1;
  unsigned int uv = 1;
  if (((unsigned int)sv < uv) == 0) ok++;                     /* 6 */

  /* hex/octal literal suffix ranges: bare large hex (no suffix) still a
     sane (64-bit-capable) value */
  long bare = 0x100000000;
  if (bare == 4294967296L) ok++;                              /* 7 */

  /* UL / ULL suffix width */
  unsigned long ulmax = 0xFFFFFFFFu;
  if (ulmax == 4294967295UL) ok++;                            /* 8 */
  unsigned long long ullbig = 0x100000000ULL;
  if (ullbig == 4294967296ULL) ok++;                          /* 9 */

  /* unsigned + signed mixed arithmetic (usual arithmetic conversions) */
  unsigned int x = 10;
  int y = -3;
  if ((x + y) == 7) ok++;                                     /* 10 */

  /* negative literal assigned to unsigned wraps */
  unsigned int neg1 = -1;
  if (neg1 == 4294967295u) ok++;                               /* 11 */

  /* unsigned modulo/hashing idiom (hot real-world path: lua/sqlite) */
  unsigned int h = 0;
  int i;
  for (i = 0; i < 5; i++) h = h * 31 + (unsigned int)i;
  if (h == 31810u) ok++;                                       /* 12 */

  /* unsigned wraparound loop bound: i-- > 0 must run exactly n times, not
     wrap into a near-infinite loop from a signed misread of `i--` */
  int count = 0;
  unsigned int n = 3;
  for (n = 3; n-- > 0;) count++;
  if (count == 3) ok++;                                        /* 13 */

  if (ok == 13) return 42;
  return ok;
}
