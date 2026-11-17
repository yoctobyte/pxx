/* C setjmp/longjmp on xtensa, call0 and windowed (feature-xtensa-c-setjmp-longjmp):
   a longjmp from 12 frames down, val 0 delivered as 1, repeated jumps to one
   buffer, two live buffers, and locals the setjmp frame keeps across it.
   The windowed run is the case that needs every window spilled. Plus a VLA
   made after setjmp (busybox's run_nofork_applet): its contents cover the 16
   bytes under the setjmp-time sp, which the caller's underflow reads after
   the longjmp (bug-xtensa-windowed-longjmp-after-a-vla-loses-the-callers-registers).
   Expected output is gcc's. tools/check_xtensa_setjmp.py */
#include <stdio.h>
#include <setjmp.h>
#include <string.h>
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
static jmp_buf vjb;
static int vdeep(int n) { volatile int pad[8]; pad[0] = n; if (!n) longjmp(vjb, 7); return vdeep(n - 1) + pad[0]; }
static int vla_run(int argc, char **argv)
{
    volatile int local = argc * 3;
    int rc = setjmp(vjb);
    if (!rc) {
        char *tmp[argc + 1];
        memcpy(tmp, argv, (argc + 1) * sizeof tmp[0]);   /* ends in NULL */
        vdeep(12 + (tmp[0] != 0));
        return -1;
    }
    return rc + local;
}
int main(void)
{
    char *av[] = { "uname", "-a", 0 };
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
    printf("vla %d\n", vla_run(2, av));
    return 0;
}
