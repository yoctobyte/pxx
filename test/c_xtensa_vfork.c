/* vfork on xtensa is the compiler's frameless body (EmitCVforkStub). Child
   and parent must both come back into the caller with its registers intact:
   locals held across the call, a deep call in the child before _exit, and
   several rounds. check() is 77 when all of that holds; main() adds system(),
   which vforks on xtensa. tools/check_xtensa_vfork.py runs it call0 (a hosted
   program) and windowed (an object under test/c_xtensa_windowed_start.S), and
   reads the clone flags from qemu -strace: qemu turns CLONE_VFORK into a fork,
   so the trace, not the result, is what tells vfork from fork.
   feature-crtl-a-real-vfork-on-xtensa */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
static int deep(int n) { volatile char pad[64]; pad[0] = (char)n; return n ? deep(n - 1) + pad[0] : 0; }
static int round_(int k, int keep1, int keep2)
{
    int st = 0, pid = vfork();
    if (pid < 0) return -100;
    if (pid == 0)
        _exit(deep(6) + k);
    if (waitpid(pid, &st, 0) != pid) return -200;
    return WEXITSTATUS(st) * 1000 + keep1 + keep2;
}
int check(void)
{
    int a = 11, b = 22, k, s = 0;
    for (k = 1; k <= 3; k++)
        s += round_(k, a * k, b);
    return (s == 69132 && a == 11 && b == 22) ? 77 : s;
}
int main(void)
{
    int r = system("exit 5");
    printf("vfork check %d system %d\n", check(), WIFEXITED(r) ? WEXITSTATUS(r) : -1);
    return 0;
}
