/* <limits.h> FOLLOWS THE TARGET'S char, AND ITS SMALL MAXIMA ARE int.
 *
 * CHAR_MIN/CHAR_MAX were -128/127 on every target, but plain char is
 * UNSIGNED on aarch64, arm32 and riscv32 (0/255 there, as gcc says). The
 * compiler now predefines __CHAR_UNSIGNED__ where char is unsigned, as gcc
 * does, and limits.h keys on it.
 * bug-c-char-min-and-char-max-ignore-the-targets-char-signedness
 *
 * Found with it: UCHAR_MAX, USHRT_MAX, UINT8_MAX and UINT16_MAX carried a U
 * suffix, but these types promote to int, so C gives the macros type int:
 * `-1 < UCHAR_MAX` was 0 (gcc 1).
 *
 * Each row states the rule, not the target's answer, so one .expected file
 * serves native and all four cross targets; native is diffed against gcc.
 */
#include <stdio.h>
#include <limits.h>
#include <stdint.h>

#define R(e) printf("%s = %d\n", #e, (int)(e))

int main(void) {
  volatile char m1 = (char)-1;
  int csigned = m1 < 0;
#if CHAR_MIN < 0
  int pp_signed = 1;
#else
  int pp_signed = 0;
#endif
  R(pp_signed == csigned);
  R((CHAR_MIN < 0) == csigned);
  R(CHAR_MIN == (csigned ? SCHAR_MIN : 0));
  R(CHAR_MAX == (csigned ? SCHAR_MAX : UCHAR_MAX));
  R((char)CHAR_MAX == CHAR_MAX);
  R((char)(CHAR_MAX + 1) == CHAR_MIN);
  R(UCHAR_MAX == 255); R(USHRT_MAX == 65535);
  R(-1 < UCHAR_MAX); R(-1 < USHRT_MAX); R(-1 < UINT8_MAX); R(-1 < UINT16_MAX);
  R(sizeof(UCHAR_MAX) == sizeof(int)); R(sizeof(USHRT_MAX) == sizeof(int));
  R(sizeof(UINT8_MAX) == sizeof(int)); R(sizeof(UINT16_MAX) == sizeof(int));
  R(-1 < UINT_MAX); /* still unsigned: 0 */
  return 0;
}
