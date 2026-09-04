/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: the extended-attribute family, over the raw syscall bridge.
 *
 * TWELVE ONE-LINE BODIES AND NO SHARED HELPER, deliberately. A helper taking a
 * syscall number would put the {path, lpath, fd} choice in a variable, and
 * that choice is the ONE thing a caller can get silently wrong: setfattr -h
 * means "act on the link, not its target", so folding l* into a flag makes a
 * wrong answer reachable by a wrong argument rather than impossible. Twelve
 * lines that each name their own syscall cannot make that mistake.
 *
 * ERRNO CONVENTION: syscall() in src/unistd.c has already turned the kernel's
 * -errno into -1 plus errno, so these return it untouched. The PAL entries use
 * the other convention (-errno handed back for the caller to translate), and
 * applying that idiom to a syscall() result overwrites the real errno with 1
 * and reports "operation not permitted" for everything -- measured in
 * src/sys/statfs.c, 2026-09-02.
 *
 * NO SIZE-0 SPECIAL CASE. get and list called with size 0 return the length a
 * buffer would need, and that is the kernel's protocol, not an error path to
 * paper over. A wrapper that turned a 0-size call into a failure would break
 * the standard two-call sizing loop.
 *
 * EVERY TARGET HAS THESE NUMBERS -- x86-64, i386, aarch64/riscv32, arm32 and
 * xtensa all carry the full family in <sys/syscall.h> -- so the #ifdef guards
 * below are not expected to fire today. They are here because the header's
 * table is partial by construction and an absent number must produce ENOSYS
 * rather than a link error.
 */
#include <sys/xattr.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>

#define XATTR_ENOSYS() do { errno = ENOSYS; return -1; } while (0)

int setxattr(const char *path, const char *name, const void *value, size_t size, int flags) {
#ifdef SYS_setxattr
  return (int)syscall(SYS_setxattr, path, name, value, (long)size, (long)flags);
#else
  (void)path; (void)name; (void)value; (void)size; (void)flags; XATTR_ENOSYS();
#endif
}

int lsetxattr(const char *path, const char *name, const void *value, size_t size, int flags) {
#ifdef SYS_lsetxattr
  return (int)syscall(SYS_lsetxattr, path, name, value, (long)size, (long)flags);
#else
  (void)path; (void)name; (void)value; (void)size; (void)flags; XATTR_ENOSYS();
#endif
}

int fsetxattr(int fd, const char *name, const void *value, size_t size, int flags) {
#ifdef SYS_fsetxattr
  return (int)syscall(SYS_fsetxattr, (long)fd, name, value, (long)size, (long)flags);
#else
  (void)fd; (void)name; (void)value; (void)size; (void)flags; XATTR_ENOSYS();
#endif
}

ssize_t getxattr(const char *path, const char *name, void *value, size_t size) {
#ifdef SYS_getxattr
  return (ssize_t)syscall(SYS_getxattr, path, name, value, (long)size);
#else
  (void)path; (void)name; (void)value; (void)size; XATTR_ENOSYS();
#endif
}

ssize_t lgetxattr(const char *path, const char *name, void *value, size_t size) {
#ifdef SYS_lgetxattr
  return (ssize_t)syscall(SYS_lgetxattr, path, name, value, (long)size);
#else
  (void)path; (void)name; (void)value; (void)size; XATTR_ENOSYS();
#endif
}

ssize_t fgetxattr(int fd, const char *name, void *value, size_t size) {
#ifdef SYS_fgetxattr
  return (ssize_t)syscall(SYS_fgetxattr, (long)fd, name, value, (long)size);
#else
  (void)fd; (void)name; (void)value; (void)size; XATTR_ENOSYS();
#endif
}

ssize_t listxattr(const char *path, char *list, size_t size) {
#ifdef SYS_listxattr
  return (ssize_t)syscall(SYS_listxattr, path, list, (long)size);
#else
  (void)path; (void)list; (void)size; XATTR_ENOSYS();
#endif
}

ssize_t llistxattr(const char *path, char *list, size_t size) {
#ifdef SYS_llistxattr
  return (ssize_t)syscall(SYS_llistxattr, path, list, (long)size);
#else
  (void)path; (void)list; (void)size; XATTR_ENOSYS();
#endif
}

ssize_t flistxattr(int fd, char *list, size_t size) {
#ifdef SYS_flistxattr
  return (ssize_t)syscall(SYS_flistxattr, (long)fd, list, (long)size);
#else
  (void)fd; (void)list; (void)size; XATTR_ENOSYS();
#endif
}

int removexattr(const char *path, const char *name) {
#ifdef SYS_removexattr
  return (int)syscall(SYS_removexattr, path, name);
#else
  (void)path; (void)name; XATTR_ENOSYS();
#endif
}

int lremovexattr(const char *path, const char *name) {
#ifdef SYS_lremovexattr
  return (int)syscall(SYS_lremovexattr, path, name);
#else
  (void)path; (void)name; XATTR_ENOSYS();
#endif
}

int fremovexattr(int fd, const char *name) {
#ifdef SYS_fremovexattr
  return (int)syscall(SYS_fremovexattr, (long)fd, name);
#else
  (void)fd; (void)name; XATTR_ENOSYS();
#endif
}
