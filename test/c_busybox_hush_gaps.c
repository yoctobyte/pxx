/* Two busybox hush (NOMMU) gaps pxx2 hit building it for Gibux:
   - libbb/vfork_daemon_rexec.c BUILD_BUG_ON(CONFIG_BUSYBOX_EXEC_PATH[0] != '/'):
     a subscripted string literal is a character in a constant expression
     (bug-c-a-subscripted-string-literal-folds-to-1).
   - hush's getpgrp(), missing from crtl's <unistd.h>.
   Run on x86-64 and xtensa; output is gcc's. */
#include <stdio.h>
#include <unistd.h>
#define EXEC_PATH "/proc/self/exe"
#define BUILD_BUG_ON(condition) ((void)sizeof(char[1 - 2*!!(condition)]))
static const int fifth = "abcdef"[4];
int main(void)
{
    BUILD_BUG_ON(EXEC_PATH[0] != '/');
    printf("%d %d %d pgrp %d\n", EXEC_PATH[0] == '/', fifth,
           (int)sizeof(char["ab" "cd"[3]]), getpgrp() == getpgid(0));
    return 0;
}
