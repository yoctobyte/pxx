/* A pxx program for Nilix/S3 (or any no-MMU xtensa loader taking a PIE):
   write, vfork, execve, wait4, exit, a pointer through a relocated literal and
   an initialised global. tools/check_xtensa_pie_link.py links it
   (test/xtensa_pie_prog.ld); on Nilix, /init2 is the program it execs.
   feature-xtensa-objects-carry-a-literal-table */
#include <unistd.h>
#include <sys/wait.h>
static const char msg[] = "hello from a pxx program\n";
static const char *p = msg;
int counter = 5;
void _start(void)
{
    int st = 0, pid;
    write(1, p, sizeof msg - 1);
    pid = vfork();
    if (pid == 0) {
        char *av[2] = { "/init2", 0 };
        char *ev[1] = { 0 };
        execve("/init2", av, ev);
        _exit(127);
    }
    if (pid > 0) waitpid(pid, &st, 0);
    _exit(counter - 5 + WEXITSTATUS(st));
}
