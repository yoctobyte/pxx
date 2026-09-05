/* Oracle for {$PACKENUM} / {$MINENUMSIZE} / {$Zn}.
 *
 * The Pascal directive and gcc's -fshort-enums are the same promise: an enum
 * takes the SMALLEST type its values fit, with a floor. So gcc built twice --
 * once with the flag and once without -- is both the oracle and its own
 * positive control, and the two answers must differ or neither line means
 * anything.
 *
 * `Wide` is the discriminating type. A naive reading of "pack enums to one
 * byte" answers 1 for it; the correct answer is 2, because 300 does not fit in
 * a byte and the directive is a MINIMUM, not a size. A test carrying only
 * `Col` would pass under both readings.
 * feature-p-packenum-and-h-minus-for-the-fpc-compiler-corpus */
#include <stdio.h>
#include <stddef.h>

enum Col  { cRed, cGreen, cBlue };
enum Wide { wA, wB = 300 };
struct R { unsigned char a; enum Col c; enum Wide w; unsigned char b; };

int main(void)
{
  printf("%zu %zu %zu %zu %zu %zu\n",
         sizeof(enum Col), sizeof(enum Wide), sizeof(struct R),
         offsetof(struct R, c), offsetof(struct R, w), offsetof(struct R, b));
  return 0;
}
