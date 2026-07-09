/* A range designator [lo ... hi] in a fn-ptr array must not inflate the array
   length: `const fptr t[3]` with a range + single overrides sizes to 3, not to the
   init-entry count. Was doubling sizeof -> loop ran off the end into NULL. -> 42. */
#include <stdio.h>
void a(void){} void b(void){} void c(void){}
typedef void (*fptr)(void);
const fptr table[3] = { [0 ... 2] = a, [0] = a, [1] = b, [2] = c };
int main(void) {
  int n = sizeof(table) / sizeof(table[0]);
  int calls = 0, i;
  for (i = 0; i < n; i++) { table[i](); calls++; }
  return (n == 3 && calls == 3) ? 42 : 1;
}
