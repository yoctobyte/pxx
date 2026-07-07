/* b192 (feature-c-corpus-tcc): C 6.3.1.3 — a cast to a narrower integer type
   truncates and re-extends by the TARGET's signedness (plain char is signed).
   A retag-only cast kept full-width bits, so tcc's imm8-fit check
   `c == (char)c` was true for 0x80 and it encoded `cmp $0x80,%eax` as a
   sign-extended imm8 (0xffffff80), miscompiling every program it built.
   Exit 42 = pass. */
static int fits8(int c) { return c == (char)c; }
int main(void) {
    if (fits8(0x7f) != 1) return 1;
    if (fits8(0x80) != 0) return 2;
    if (fits8(-128) != 1) return 3;
    if (fits8(-129) != 0) return 4;
    if (fits8(0x800) != 0) return 5;
    if ((char)0x80 != -128) return 6;
    if ((signed char)0xff != -1) return 7;
    if ((unsigned char)-1 != 255) return 8;
    if ((short)0x18000 != -32768) return 9;
    if ((unsigned short)-1 != 65535) return 10;
    if ((int)0x100000001LL != 1) return 11;
    if ((int)0xffffffffLL != -1) return 12;
    return 42;
}
