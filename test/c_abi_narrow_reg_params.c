/* A byte-sized parameter must be spilled FROM THE REGISTER IT ARRIVED IN.

   This exists because of a defect that a pxx-vs-pxx test could catch and no
   pxx-vs-pxx test did. When the SysV callee spill started reading its slot
   assignment from ABISysVArgPlace, one reader of the old bank counter was left
   behind -- `if (intIdx = 0) or (intIdx = 1) then EmitB($40)`, the REX prefix
   that makes dil and sil addressable at all. The oracle had already advanced
   intIdx past the current slot, so for a 1-byte parameter in rdi or rsi the
   prefix was dropped, and `mov %sil, off(%rbp)` assembled instead as
   `mov %dh, off(%rbp)`: the HIGH BYTE OF RDX, a different register entirely.

   It is not a convention question, which is why self-consistency does not save
   it: the callee reads the wrong register whatever the caller did. It survived
   byte-identity checks across four targets because every C source in that
   corpus happened to pass its narrow arguments in rdx or later, and it
   survived the conversion itself because it sits in a nested `if` rather than
   in a branch condition or a case selector, where every other reader was.

   Each of the six integer argument registers gets a narrow parameter here, and
   the values are distinct primes so a swap, a truncation or a neighbouring
   register cannot produce the expected sum by coincidence.
   bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee */
#include <stdio.h>

static int take_narrow(char a, char b, short c, short d, int e, char f)
{ return a * 1000000 + b * 100000 + c * 10000 + d * 100 + e * 10 + f; }

/* THE NEGATIVE CONTROL, and the first version of it was not one. Two WIDE
   parameters take rdi and rsi, so every narrow parameter here lands in rdx,
   rcx, r8 or r9 -- registers whose low byte is addressable without a REX
   prefix, and which the defect therefore never touched. This row must stay
   GREEN against the broken compiler; if it ever goes red with take_narrow, the
   cause is wider than the prefix.
   Written first as `(long w, char a, ...)`, which put `a` in sil and made it a
   second positive dressed as a control -- it failed against the broken
   compiler exactly as the row above did, which is how the mistake surfaced. */
static int take_shifted(long w, long x, char a, char b, short c, int d)
{ return (int)w * 1000000 + (int)x * 100000 + a * 10000 + b * 100 + c * 10 + d; }

int main(void)
{
  int n = take_narrow(3, 5, 7, 11, 13, 17);
  int s = take_shifted(2, 3, 5, 7, 11, 13);
  printf("narrow %d\n", n);
  printf("shifted %d\n", s);
  if (n != 3 * 1000000 + 5 * 100000 + 7 * 10000 + 11 * 100 + 13 * 10 + 17) return 1;
  if (s != 2 * 1000000 + 3 * 100000 + 5 * 10000 + 7 * 100 + 11 * 10 + 13) return 2;
  return 42;
}
