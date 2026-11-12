/* chroot() reaches the kernel (it was an ENOSYS stub until 2026-11-12, found
   by Gibux's switch_root test). Unprivileged, the answers are the kernel's:
   a missing path is ENOENT (the lookup comes before the capability check)
   and an existing one is EPERM. Root gets 0 for "/", which changes nothing.
   The stub said ENOSYS to both. Output is gcc's. */
#include <stdio.h>
#include <errno.h>
#include <unistd.h>

int main(void)
{
    int r1, e1, r2, e2;
    errno = 0; r1 = chroot("/nonexistent-pxx-chroot-dir"); e1 = errno;
    errno = 0; r2 = chroot("/"); e2 = errno;
    printf("%d %s\n", r1, e1 == ENOENT ? "ENOENT" : e1 == ENOSYS ? "ENOSYS" : "other");
    if (geteuid() == 0)
        printf("%s\n", r2 == 0 ? "root-ok" : "root-fail");
    else
        printf("%d %s\n", r2, e2 == EPERM ? "EPERM" : e2 == ENOSYS ? "ENOSYS" : "other");
    return 0;
}
