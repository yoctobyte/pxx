/* C99 6.4.4.1: an integer constant's SUFFIX re-runs the type ladder, it does not
   widen the rung the unsuffixed ladder picked.

   `0x9745DC78L` is 2537528440, which overflows int but fits BOTH unsigned int
   and (signed) long. Unsuffixed, the hex ladder stops at unsigned int; with `L`
   the candidate list is long, unsigned long — so it is a positive LONG.

   Typing it unsigned long instead converts the negative int32 it is compared
   with into a huge unsigned value, and the comparison silently flips. That is
   csmith seed 79 (bug-c-csmith-seed-79-miscompile-vs-gcc), whose 1588 lines
   reduced to exactly this line. Every row's expectation is gcc's. */

#include <stdio.h>
#include <stdint.h>

int32_t g = -1970268214;

int main(void) {
  printf("hexL   %d\n", 0x9745DC78L  > g);   /* long: 2537528440 > -1970268214 */
  printf("hex    %d\n", 0x9745DC78   > g);   /* unsigned int, but still > */
  printf("decL   %d\n", 2537528440L  > g);   /* decimal ladder, always signed here */
  printf("hexLL  %d\n", 0x9745DC78LL > g);   /* long long, same as long here */
  printf("hexU   %d\n", 0x9745DC78UL > g);   /* UNSIGNED long: g converts up, so 0 */
  printf("plain  %d\n", 0x7FFFFFFFL  > g);   /* fits int, unaffected */
  return 0;
}
