/* gcc's case ranges, `case LO ... HI:` (NetBSD's rump sources use them:
   `case 'a' ... 'z':`). Signed and unsigned selectors, negative bounds, a
   range beside single labels, an empty range (LO > HI matches nothing), and
   fall-through into and out of a range. The output is gcc's. */
#include <stdio.h>

static int cls(int c) {
  switch (c) {
  case 'a' ... 'z': return 1;
  case 'A' ... 'Z': return 2;
  case '0' ... '9': return 3;
  case '_': return 4;
  default: return 0;
  }
}

static int neg(int v) {
  switch (v) {
  case -10 ... -1: return -1;
  case 0: return 0;
  case 1 ... 1000000: return 1;
  default: return 9;
  }
}

static int uns(unsigned u) {
  switch (u) {
  case 0 ... 9: return 1;
  case 0xFFFFFFF0u ... 0xFFFFFFFFu: return 2;
  default: return 0;
  }
}

static int empty(int v) {
  switch (v) {
  case 5 ... 3: return 1;
  default: return 0;
  }
}

static int fall(int v) {
  int r = 0;
  switch (v) {
  case 1: r += 1;
  case 2 ... 4: r += 10;
  case 5: r += 100; break;
  default: r = -1;
  }
  return r;
}

int main(void) {
  const char *s = "aZ5_?";
  int i;
  for (i = 0; s[i]; i++) printf("%d ", cls(s[i]));
  printf("\n%d %d %d %d %d %d\n", neg(-11), neg(-10), neg(-1), neg(0), neg(1000000), neg(1000001));
  printf("%d %d %d %d\n", uns(9), uns(10), uns(0xFFFFFFF0u), uns(0xFFFFFFFFu));
  printf("%d %d %d\n", empty(3), empty(4), empty(5));
  printf("%d %d %d %d %d\n", fall(1), fall(2), fall(4), fall(5), fall(6));
  return 0;
}
