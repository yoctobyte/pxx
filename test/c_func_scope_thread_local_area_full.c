#include <stdio.h>
static int big(void) { static __thread char b[2000]; static __thread int n = 5; b[1999]++; return b[1999] + n++; }
int main(void) { int a = big(); int b = big(); printf("%d %d\n", a, b); return 0; }
