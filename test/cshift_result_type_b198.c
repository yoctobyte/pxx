/* Regression (bug-c-shift-result-type-battery-00200): C99 6.5.7p3 — a shift's
 * result type is the PROMOTED LEFT operand; the right (count) type is
 * irrelevant. pxx applied usual-arithmetic-conversions over BOTH operands, so a
 * wide/unsigned shift COUNT changed the result's signedness: `(short)1 <<
 * (unsigned long)1` came out unsigned instead of signed int. Mirrors 00200's
 * contract: PTYPE(X) (sign*size of the base) must equal PTYPE(X<<count) for
 * EVERY count type. Returns 42. */
#include <stdio.h>
#define PTYPE(M) (((M) < 0 || -(M) < 0) ? -1 : 1) * (int) sizeof((M) + 0)
#define CHECK(X, T) do { if (PTYPE(X) != PTYPE((X) << (T)1)) fails++; } while (0)
#define ALLC(X) do {                 \
    CHECK(X, short); CHECK(X, unsigned short);   \
    CHECK(X, int);   CHECK(X, unsigned int);     \
    CHECK(X, long);  CHECK(X, unsigned long);    \
    CHECK(X, long long); CHECK(X, unsigned long long); \
  } while (0)
int main(void) {
  int fails = 0;
  ALLC((short)1);   ALLC((unsigned short)1);
  ALLC((int)1);     ALLC((unsigned int)1);
  ALLC((long)1);    ALLC((unsigned long)1);
  ALLC((long long)1); ALLC((unsigned long long)1);
  if (fails) { printf("fails=%d\n", fails); return fails; }
  return 42;
}
