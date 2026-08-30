/* clz/ctz at ZERO must TERMINATE. Without the guards in lib/crtl/src/stdlib.c
   these spin forever: no shift of 0 ever reaches the bit the loop waits for, so
   the program never returns rather than returning something wrong.

   All SIX spellings, because the two 32-bit and four 64-bit forms route through
   four separate routines and guarding one proves nothing about the others --
   a census found all six hanging and the other twelve builtins fine.

   The values are the operand width, matching x86 lzcnt/tzcnt and gcc's constant
   folder. C leaves clz/ctz UNDEFINED at zero, so this pins OUR convention; it is
   deliberately not claimed as conformance. Note a checksum-style oracle cannot
   validate these numbers -- the csmith program that found the hang prints the
   same checksum whether the guard returns 0, 7 or 63.
   bug-c-clz-ctz-of-zero-spin-forever-in-crtl */
int printf(const char *, ...);
int main(void) {
  volatile unsigned int u = 0;
  volatile unsigned long ul = 0;
  volatile unsigned long long ull = 0;
  int a = __builtin_clz(u),   b = __builtin_clzl(ul),  c = __builtin_clzll(ull);
  int d = __builtin_ctz(u),   e = __builtin_ctzl(ul),  f = __builtin_ctzll(ull);
  printf("clz=%d clzl=%d clzll=%d ctz=%d ctzl=%d ctzll=%d\n", a, b, c, d, e, f);
  /* ffs IS defined at zero and must keep answering 0 -- it was already guarded,
     and the fix must not disturb it. */
  if (__builtin_ffsl((long)ul) != 0) return 1;
  if (a == 32 && b == 64 && c == 64 && d == 32 && e == 64 && f == 64) return 42;
  return 1;
}
