/* C setjmp/longjmp on xtensa, call0 and windowed (feature-xtensa-c-setjmp-longjmp):
   a longjmp from 12 frames down, val 0 delivered as 1, repeated jumps to one
   buffer, two live buffers, and locals the setjmp frame keeps across it.
   The windowed run is the case that needs every window spilled. Expected
   output is gcc's. tools/check_xtensa_setjmp.py */
#include <stdio.h>
#include <setjmp.h>
static jmp_buf outer, inner;
static int depth_reached;
static int dive(int n, int val)
{
    volatile char pad[24];
    pad[0] = (char)n;
    if (n == 0) { depth_reached = 1; longjmp(outer, val); }
    return dive(n - 1, val) + pad[0];
}
static int middle(int k)
{
    volatile int keep = k * 7;
    int r = setjmp(inner);
    if (r == 0) { longjmp(inner, k + 40); }
    return r + keep;
}
int main(void)
{
    volatile int a = 5, b = 9, round = 0;
    int r, total = 0;
    r = setjmp(outer);
    total += r;
    round++;
    if (round == 1) dive(12, 3);
    if (round == 2) dive(4, 0);
    if (round == 3) dive(1, 77);
    printf("rounds %d total %d depth %d a %d b %d middle %d %d\n",
           round, total, depth_reached, a, b, middle(2), middle(5));
    return 0;
}
