/* Host for test_library_exports.pas: a foreign caller marshalling the C
   convention into a pxx `library`'s declared export surface. */
#include <stdio.h>

int PxxLibAdd(int a, int b);
int PxxLibMul(int a, int b);
int PxxLibNegate(int a);

int main(void)
{
  printf("%d\n", PxxLibAdd(20, 22));
  printf("%d\n", PxxLibMul(6, 7));
  printf("%d\n", PxxLibNegate(42));
  return 0;
}
