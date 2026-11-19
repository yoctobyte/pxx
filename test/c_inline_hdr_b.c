/* Includes the same inline definition as c_inline_hdr_a.c and calls both
   `twice` and a.c's `quad`. Before the fix both objects exported a strong
   `twice` and --link refused the pair as a multiple definition. */
#include <stdio.h>
#include "c_inline_hdr.h"
int quad(int x);
int main(void) { printf("%d %d\n", twice(21), quad(5)); return 0; }
