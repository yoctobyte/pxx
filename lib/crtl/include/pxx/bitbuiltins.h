/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: the bodies behind gcc's bit builtins (__builtin_clz ->
 * __pxx_builtin_clz32, ...; cfront renames the calls), in ONE place for the
 * two ways they are compiled:
 *   - src/stdlib.c includes this with __PXX_BI_SC empty: ordinary external
 *     functions of crtl, auto-pulled through <stdlib.h> as before;
 *   - <stdlib.h> includes it with __PXX_BI_SC `static` under
 *     __PXX_SYSTEM_STDLIB__ (an --emit-obj --system-libs object, linked
 *     against the host libc): stdlib.c is not pulled there and no libc
 *     exports these names, so each unit carries its own private copy.
 *     wlroots' wlr_data_offer.c (__builtin_popcount) linked against glibc
 *     was refused for the import. bug-c-system-libs-objects-import-crtl-only-names
 * Not guarded against a second inclusion on purpose: each includer
 * includes it once, with its own __PXX_BI_SC.
 */
__PXX_BI_SC int __pxx_builtin_clz32(unsigned int x) {
  int n = 0;
  if (x == 0u) return 32;
  while (!(x & 0x80000000u)) { x <<= 1; n++; }
  return n;
}

__PXX_BI_SC int __pxx_builtin_clz64(unsigned long long x) {
  int n = 0;
  if (x == 0ull) return 64;
  while (!(x & 0x8000000000000000ull)) { x <<= 1; n++; }
  return n;
}

__PXX_BI_SC int __pxx_builtin_ctz32(unsigned int x) {
  int n = 0;
  if (x == 0u) return 32;
  while (!(x & 1u)) { x >>= 1; n++; }
  return n;
}

__PXX_BI_SC int __pxx_builtin_ctz64(unsigned long long x) {
  int n = 0;
  if (x == 0ull) return 64;
  while (!(x & 1ull)) { x >>= 1; n++; }
  return n;
}

__PXX_BI_SC int __pxx_builtin_popcount32(unsigned int x) {
  int n = 0;
  while (x) { n += (int)(x & 1u); x >>= 1; }
  return n;
}

__PXX_BI_SC int __pxx_builtin_popcount64(unsigned long long x) {
  int n = 0;
  while (x) { n += (int)(x & 1ull); x >>= 1; }
  return n;
}

/* ffs: 1 + index of the least significant set bit, 0 for a zero argument.
   Unlike clz/ctz, ffs is DEFINED at zero -- do not route it through ctz. */
__PXX_BI_SC int __pxx_builtin_ffs32(unsigned int x) {
  int n = 1;
  if (x == 0u) return 0;
  while (!(x & 1u)) { x >>= 1; n++; }
  return n;
}

__PXX_BI_SC int __pxx_builtin_ffs64(unsigned long long x) {
  int n = 1;
  if (x == 0ull) return 0;
  while (!(x & 1ull)) { x >>= 1; n++; }
  return n;
}

/* parity: number of set bits mod 2. Defined at zero (answers 0). */
__PXX_BI_SC int __pxx_builtin_parity32(unsigned int x) {
  int n = 0;
  while (x) { n ^= (int)(x & 1u); x >>= 1; }
  return n;
}

__PXX_BI_SC int __pxx_builtin_parity64(unsigned long long x) {
  int n = 0;
  while (x) { n ^= (int)(x & 1ull); x >>= 1; }
  return n;
}

/* bswap: reverse the byte order. Returns the same width it took. */
__PXX_BI_SC unsigned short __pxx_builtin_bswap16(unsigned short x) {
  return (unsigned short)(((x & 0x00FFu) << 8) | ((x & 0xFF00u) >> 8));
}

__PXX_BI_SC unsigned int __pxx_builtin_bswap32(unsigned int x) {
  return ((x & 0x000000FFu) << 24) | ((x & 0x0000FF00u) << 8) |
         ((x & 0x00FF0000u) >> 8)  | ((x & 0xFF000000u) >> 24);
}

__PXX_BI_SC unsigned long long __pxx_builtin_bswap64(unsigned long long x) {
  return ((x & 0x00000000000000FFull) << 56) | ((x & 0x000000000000FF00ull) << 40) |
         ((x & 0x0000000000FF0000ull) << 24) | ((x & 0x00000000FF000000ull) << 8)  |
         ((x & 0x000000FF00000000ull) >> 8)  | ((x & 0x0000FF0000000000ull) >> 24) |
         ((x & 0x00FF000000000000ull) >> 40) | ((x & 0xFF00000000000000ull) >> 56);
}
