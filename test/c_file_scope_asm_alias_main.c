#include <stdio.h>
long ufetch_long(const long *p);
long ufetch_ptr(const long *p);
int mutex_spin_exit(int x);
int overridden(int x);
extern int counter_alias;
int old_api(void);

/* a strong definition here beats the object's weak alias */
int overridden(int x) { return -x; }

int main(void)
{
  long v = 41;
  counter_alias += 1;
  printf("%ld %ld %d %d %d %d\n", ufetch_long(&v), ufetch_ptr(&v),
         mutex_spin_exit(2), overridden(7), counter_alias, old_api());
  return 0;
}
