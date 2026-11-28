/* Binary integer literals, 0b101 (GNU C, C23), in code, a case label, a
   suffix, and #if. amdgpu's link_dp_capability.c `case 0b001:`.
   bug-c-binary-integer-literals-are-not-lexed. Expected output is gcc's. */
#include <stdio.h>
#if 0b101 != 5
#error binary in #if
#endif
#define MASK 0B1111u
static int rate(int bw) {
  switch (bw) {
  case 0b001: return 9;
  case 0b010: return 18;
  case 0b100: return 36;
  }
  return 0;
}
int main(void) {
  unsigned long long big = 0b1000000000000000000000000000000000000000000000000000000000000001ULL;
  printf("%d %d %d %u\n", rate(1), rate(2), rate(4), MASK);
  printf("%d %llu %d\n", 0b11 + 0b1, big, (int)sizeof(0b11111111111111111111111111111111));
  return 0;
}
