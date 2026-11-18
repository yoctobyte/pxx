#include <stdio.h>
struct domain { int x; };
struct domain arpdomain = { 30 }, inetdomain = { 12 };
int sum_domains(void);
int main(void) { printf("%d\n", sum_domains()); return 0; }
