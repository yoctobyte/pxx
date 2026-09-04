/* SPDX-License-Identifier: Zlib */
/* _Generic AND THE long RANK: the rank is a property of the TYPE, not of how it
 * was spelled at one occurrence, and pxx used to read it from the `long` TOKENS
 * counted in the declaration being parsed.
 *
 * ROW 2 IS THE ONE THAT WAS WRONG — measured by ablation, not assumed, and it
 * is not the row I expected. `typedef long long TLL;` selected the `long:` arm
 * where gcc selects `long long:`. TTypeKind collapses both onto tyInt64
 * wherever a pointer is eight bytes, so with no rank recorded the two arms are
 * indistinguishable by kind and `long:` simply matches first. The bug is
 * therefore NATIVE-ONLY in shape: on a 32-bit target the kinds differ
 * (tyInt32 vs tyInt64) and the arm is picked correctly for the wrong reason.
 * Measured on x86-64; this file makes no claim about what i386 did before.
 *
 * ROW 3, THE ALIAS, WAS ACCIDENTALLY RIGHT — same collapse, opposite luck: TLA
 * is `long` and the `long:` arm matched it by kind. That is why row 3 cannot
 * carry this test on its own, and why rows 1/4/5 are here too: three of the
 * five rows pass on a compiler that records no rank at all, so any one of them
 * alone would be a row that cannot fail.
 *
 * Found while adding the conflicting-typedef refusal, which needs the rank to
 * survive a typedef so `typedef long T; typedef T Alias; typedef long Alias;`
 * stays legal. _Generic reads the same two flags.
 *
 * gcc -O0 is the oracle at BOTH widths and the transcript is width-independent.
 * bug-c-the-frontend-takes-the-last-of-two-conflicting-typedefs-silently
 */
/* _Generic MUST SEE THROUGH A TYPEDEF ALIAS, because the long RANK is a property
 * of the type and not of how it was spelled at one occurrence.
 *
 * `typedef long TL; typedef TL TLA;` — TLA is `long`, and gcc selects the
 * `long:` arm for it. pxx read its rank from the `long` TOKENS counted in the
 * declaration being parsed, and an alias spells none, so TLA arrived rank 0 and
 * missed the arm. ROW 3 IS THE ONE THAT CHANGED; rows 1/2/4/5 are the direct
 * spellings, which were always right and would be the casualties of a fix that
 * over-reached.
 *
 * TTypeKind cannot answer this question at all: `long` and `long long` are both
 * tyInt64 wherever a pointer is eight bytes, which is why the rank exists
 * beside the kind (SymCLongRank does the same for symbols).
 *
 * Found while adding the conflicting-typedef refusal — the rank had to be
 * inherited for `typedef long T; typedef T Alias; typedef long Alias;` to stay
 * legal, and _Generic reads the same two flags, so it was silently wrong for
 * every aliased spelling until then.
 *
 * gcc -O0 is the oracle at BOTH widths and the transcript is width-independent.
 * bug-c-the-frontend-takes-the-last-of-two-conflicting-typedefs-silently
 */
#include <stdio.h>
typedef long TL;
typedef long long TLL;
typedef TL TLA;
#define NAME(x) _Generic((x), long: "long", long long: "longlong", int: "int", default: "other")
int main(void){
  TL a = 0; TLL b = 0; TLA c = 0; long d = 0; long long e = 0;
  printf("1 %s\n", NAME(a));
  printf("2 %s\n", NAME(b));
  printf("3 %s\n", NAME(c));
  printf("4 %s\n", NAME(d));
  printf("5 %s\n", NAME(e));
  return 0;
}
