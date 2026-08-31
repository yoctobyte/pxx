#include <stdio.h>
struct Pair { int a; int b; };
extern int take_pair(struct Pair p);
extern struct Pair make_pair(int a, int b);
int main(void){
  struct Pair p; p.a = 3; p.b = 7;
  printf("take %d\n", take_pair(p));
  struct Pair q = make_pair(4, 9);
  printf("make %d %d\n", q.a, q.b);
  return 0;
}
