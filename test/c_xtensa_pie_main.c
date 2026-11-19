/* A C program with main() as a PIE for Rainyday/S3: the windowed posix
   object's process entry (app_main) reads argc/argv/envp from the initial
   stack, runs the initializers and calls main. Uses crtl (printf, malloc,
   environ, vfork/execve/waitpid). tools/check_xtensa_pie_link.py links it
   with `-e app_main`; on Rainyday (QEMU) it printed PMAIN-OK on 2026-11-19.
   feature-xtensa-gibux-user-programs-as-et-dyn-pie */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
extern char **environ;
static const char *greet = "pxx main";
int counter = 7;
int main(int argc, char **argv)
{
    char *m = malloc(64);
    strcpy(m, greet);
    printf("%s: argc=%d argv0=%s counter=%d\n", m, argc, argv[0], counter);
    if (argc == 1) {
        int st = 0, pid = vfork();
        if (pid == 0) {
            char *av[] = { argv[0], "child", 0 };
            execve(argv[0], av, environ);
            _exit(127);
        }
        waitpid(pid, &st, 0);
        printf("PMAIN-%s\n", WEXITSTATUS(st) == 3 ? "OK" : "BAD");
        return 0;
    }
    return 3;
}
