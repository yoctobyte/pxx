/* asm goto (x86-64), against gcc: a conditional jump to one of two labels,
   %l by number and by name, a label that is never taken, a jump BACKWARD to
   a label before the statement, and the fall-through path. rump repro g14c's
   gz() is the first case verbatim. feature-c-inline-asm-goto */
#include <stdio.h>
static int gz(int x) { asm goto("testl %0,%0; jz %l1" :: "r"(x) :: zero); return 1; zero: return 0; }
static int sign(long v)
{
    asm goto("testq %0,%0\n\tjs %l[neg]\n\tjz %l[nil]" :: "r"(v) :: neg, nil);
    return 1;
neg: return -1;
nil: return 0;
}
static int countdown(int n)
{
    int steps = 0;
again:
    steps++;
    n--;
    asm goto("cmpl $0, %0; jg %l1" :: "r"(n) :: again);
    return steps;
}
int main(void)
{
    printf("gz %d %d sign %d %d %d count %d\n", gz(0), gz(5), sign(-3), sign(0), sign(9), countdown(4));
    return 0;
}
