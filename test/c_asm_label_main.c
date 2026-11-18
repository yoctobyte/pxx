#include <stdio.h>
int bar(int);
int callfoo(void);
int callext(void);
int real_ext(int x) { return x * 100; }
extern long time_second;
void set_second(long s);
int use_spin(void);
void mutex_spin_exit(int *m);
extern int vnodeops;
int read_ops(void);
int main(void)
{
  int m = 4;
  set_second(1234);
  mutex_spin_exit(&m);
  printf("%d %d %d %ld %d %d %d %d\n", bar(5), callfoo(), callext(), time_second,
         use_spin(), m, vnodeops, read_ops());
  return 0;
}
