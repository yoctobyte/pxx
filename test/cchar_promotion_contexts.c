/* Plain `char` is promoted in EVERY context C promotes it, not just in
   arithmetic. cchar_plain_signedness.c covers the fold-vs-runtime split; this
   covers the contexts that a value-level promotion is easy to forget, each of
   which was measured wrong against gcc while the fix was being written:

     cast to a float type, assignment, declaration initializer, the ternary
     arms, the switch controlling expression, a prototyped call argument, and a
     varargs argument.

   All expectations are gcc's, guarded on the target's psABI so the test states
   the right answer everywhere rather than only where it was written.
   bug-cfront-plain-char-is-unsigned-and-folds-inconsistently */

#if defined(__x86_64__) || defined(__i386__)
#  define PLAIN_CHAR_SIGNED 1
#else
#  define PLAIN_CHAR_SIGNED 0
#endif

#if PLAIN_CHAR_SIGNED
#  define CH_FF (-1)
#  define CH_80 (-128)
#else
#  define CH_FF 255
#  define CH_80 128
#endif

char gff = (char)0xFF;
char garr[2] = { (char)0xFF, 65 };
struct S { char a; };
struct S gs = { (char)0xFF };

static int takes_int(int x) { return x; }
static int sum3(int a, int b, int c) { return a + b + c; }

int main(void) {
    char c = (char)0xFF;
    char lo = (char)0x80;
    char *p = &c;

    /* cast to a floating type — goes through a different lowering branch than
       the integer casts, and exits before the narrowing path */
    if ((double)c != (double)CH_FF) return 1;
    if ((float)c  != (float)CH_FF)  return 2;
    if ((double)lo != (double)CH_80) return 3;

    /* assignment and declaration initializer */
    { int t = c;      if (t != CH_FF) return 4; }
    { int t; t = c;   if (t != CH_FF) return 5; }
    { long t = c;     if (t != CH_FF) return 6; }
    { double t = c;   if (t != (double)CH_FF) return 7; }

    /* ternary arms take the usual arithmetic conversions */
    { int t = (1 ? c : 0);        if (t != CH_FF) return 8; }
    { int t = (0 ? 0 : c);        if (t != CH_FF) return 9; }

    /* switch controlling expression is promoted, so a negative char reaches a
       negative case label instead of falling to default */
    switch (c) { case CH_FF: break; default: return 10; }
    switch (lo) { case CH_80: break; default: return 11; }

    /* call arguments: prototyped (converted to the parameter type) and
       varargs (default argument promotions) */
    if (takes_int(c) != CH_FF) return 12;
    if (sum3(c, c, c) != 3 * CH_FF) return 13;

    /* every lvalue flavour, not just a local */
    if (takes_int(gff) != CH_FF) return 14;
    if (takes_int(garr[0]) != CH_FF) return 15;
    if (takes_int(gs.a) != CH_FF) return 16;
    if (takes_int(*p) != CH_FF) return 17;

    /* a char[] designator DECAYS — it must never be promoted as a char value.
       Promoting it turned every string call into arithmetic on the address and
       segfaulted the C runtime before main's first statement. */
    { const char *s = "AB"; if (s[0] != 'A' || s[1] != 'B') return 18; }
    { char buf[3]; buf[0] = 'x'; buf[1] = 0; if (buf[0] != 'x') return 19; }

    /* explicit signed/unsigned char are unaffected by the target property */
    { int t = (signed char)0xFF;   if (t != -1)  return 20; }
    { int t = (unsigned char)0xFF; if (t != 255) return 21; }

    /* assigning back into a char re-truncates to the same byte */
    { char b = c; if ((int)b != CH_FF) return 22; }

    return 42;
}
