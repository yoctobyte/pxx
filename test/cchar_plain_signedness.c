/* Plain `char` takes the TARGET psABI's signedness — signed on x86-64/i386,
   unsigned on aarch64/arm32/riscv — and the constant folder and codegen must
   agree, because they used to not: the folder treated tyChar as signed while
   codegen treated it as unsigned, so `(char)-1 < 0` folded to 1 while the same
   comparison on a variable gave 0. An expression's meaning depended on whether
   its value happened to be known at compile time.
   bug-cfront-plain-char-is-unsigned-and-folds-inconsistently

   Expectations are gcc's, measured. Guarded on the target so this test states
   the right answer everywhere rather than only where it was written. */

#if defined(__x86_64__) || defined(__i386__)
#  define PLAIN_CHAR_SIGNED 1
#else
#  define PLAIN_CHAR_SIGNED 0
#endif

#if PLAIN_CHAR_SIGNED
#  define CH_FF (-1)
#else
#  define CH_FF 255
#endif

char g = -1;
char garr[2] = { -1, 0 };

int main(void) {
    char c = (char)0xFF;
    char *p = &c;

    if ((int)c != CH_FF) return 1;
    if ((c < 0) != PLAIN_CHAR_SIGNED) return 2;
    if (c + 0 != CH_FF) return 3;
    if ((int)g != CH_FF) return 4;
    if ((int)garr[0] != CH_FF) return 5;
    if ((int)*p != CH_FF) return 6;

    /* Explicitly signed/unsigned char are unaffected by the target property. */
    if ((int)(signed char)0xFF != -1) return 7;
    if ((int)(unsigned char)0xFF != 255) return 8;

    /* The whole point: FOLDED and RUNTIME forms of one expression must agree. */
    {
        char rt = (char)-1;
        if (((char)-1 < 0) != (rt < 0)) return 9;
        if ((int)(char)-1 != (int)rt) return 10;
    }

    /* UTF-8 continuation-byte probe — `*p < 0` is how real code spots them. */
    {
        const char *s = "\xC3\xA9x";
        const char *q;
        int n = 0;
        for (q = s; *q; q++) if (*q < 0) n++;
        if (n != (PLAIN_CHAR_SIGNED ? 2 : 0)) return 11;
    }

    return 42;
}
