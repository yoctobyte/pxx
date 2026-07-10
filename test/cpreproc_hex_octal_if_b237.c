/* b237 (Track C, cpreproc): #if constant expressions parse HEX (0x..) and OCTAL
   (0NN) integer literals. CPExprAtom / CPParsePoolNumber were decimal-only, so
   `0x7fff0000` stopped at the 'x' and evaluated to 0 — `#if 0x10 > 0` was FALSE.
   In sqlite this made `#if SQLITE_MAX_MMAP_SIZE>0` (0x7fff0000) FALSE at the
   unixFile struct (dropping the mmap fields) while other sites kept the guarded
   code, so `pFile->mmapSize` resolved to offset 0 and read garbage. Exit 42=pass. */
int main(void) {
#if 0x10 > 0
#else
    return 1;                 /* hex literal must be non-zero */
#endif
#if 0x7fff0000 > 0
#else
    return 2;                 /* large hex must stay positive */
#endif
#if 0xFF != 255
    return 3;
#endif
#if 010 != 8
    return 4;                 /* octal */
#endif
#if 0x0
    return 5;                 /* 0x0 is falsy */
#endif
#if (1 << 16) != 0x10000
    return 6;                 /* hex on the RHS of a comparison */
#endif
#define MMAP 0x7fff0000
#if !(MMAP > 0)
    return 7;                 /* hex via a macro value */
#endif
    return 42;
}
