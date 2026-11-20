/* Declarators after a function prototype in one declaration are declared.
   `T f(int), g(int), x;` declared f and dropped the rest (ParseCSubroutine
   skipped to the `;`). xedit.h declares two prototypes this way.
   bug-c-declarators-after-a-prototype-are-dropped */
#include <stdio.h>
typedef int Acc;
Acc first(const char *), second(const char *, int *);
int a1, f1(int);
static int f2(int), b2 = 2;
int f3(int), f4(int), c3;
extern int f5(int) __attribute__((unused)), d5;
int third(int), fourth;
int main(void)
{
  int e = 0;
  a1 = 1; c3 = 3; fourth = 4; d5 = 5;
  { int r1 = first("ab"), r2 = second("abc", &e);   /* sequenced: argument order is unspecified */
    printf("%d %d %d\n", r1, r2, e); }
  printf("%d %d %d %d %d %d %d\n", f1(a1), f2(b2), f3(1), f4(2), c3, f5(5), d5);
  printf("%d\n", third(fourth));
  return 0;
}
Acc first(const char *s) { return s[0]; }
Acc second(const char *s, int *e) { *e = 3; return s[2]; }
int f1(int x) { return x + 100; }
static int f2(int x) { return x + 200; }
int f3(int x) { return x + 300; }
int f4(int x) { return x + 400; }
int f5(int x) { return x + 500; }
int d5;
int third(int x) { return x * 10; }
