/* pivot_root(2) reaches the kernel from crtl.
 *
 * THE OBVIOUS ASSERTION IS THE ONE THAT CANNOT FAIL. `pivot_root(...) == -1'
 * is ALSO what crtl's own #else arm returns when SYS_pivot_root is undefined
 * for the target -- so a row asserting -1 agrees with a runtime that has no
 * implementation at all, which is the state this function was in until
 * 2026-09-16. The discriminator is ERRNO: ENOSYS means we never made a
 * syscall, anything else means the kernel answered and refused.
 *
 * Deliberately NOT asserting WHICH refusal. Unprivileged gives EPERM, root in
 * a container gives EINVAL or EBUSY, and a path that does not exist gives
 * ENOENT -- all correct, all environment-dependent. Pinning one would make
 * this row a report about the box it last ran on.
 *
 * Declared the way busybox declares it (util-linux/pivot_root.c:35) rather
 * than by including <sys/mount.h>, because that spelling -- a bare extern with
 * no header -- is what has to resolve for the freestanding busybox link to
 * work, and it is the route the crtl name map exists to serve.
 */
#include <stdio.h>
#include <errno.h>

extern int pivot_root(const char *new_root, const char *put_old);

int main(void) {
  int r;
  errno = 0;
  r = pivot_root("/nonexistent-pxx-new-root", "/nonexistent-pxx-put-old");
  printf("%d %d\n", r == -1, errno != 0 && errno != ENOSYS);
  return 0;
}
