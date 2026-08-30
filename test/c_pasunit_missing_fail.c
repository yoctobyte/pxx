/* A missing Pascal unit must be diagnosed AT THE INCLUDE, in C's vocabulary,
   in the author's own spelling, and without leaking the preprocessor's
   internal __pxx_pascal_unit marker into the context window.

   The include is deliberately NOT on line 1: the defect was a fixed +1 offset,
   so a line-1 include reported line 2 and a line-8 include reported 9. A test
   whose include sits on line 1 would pass against an off-by-one that merely
   reported "1" for a different reason.
   bug-c-a-missing-pascal-unit-diagnostic-points-at-the-wrong-line-and-leaks-an-internal-marker */
int a;
int b;
int c;
#include "definitely_no_such_unit.pas"
int main(void) { return 0; }
