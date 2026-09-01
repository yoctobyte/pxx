/* The C host that DEFINES what c_obj_import_pascal.pas imports. */
#include <stdio.h>

int ImpCount = 5;
int ImpA = 10;
int ImpB = 20;

extern int pxx_sum(void);
extern void pxx_bump(void);

int main(void)
{
  printf("%d ", pxx_sum());
  pxx_bump();
  printf("%d\n", ImpCount);
  return 0;
}
