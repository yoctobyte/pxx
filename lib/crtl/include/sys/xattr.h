/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_XATTR_H
#define PXX_CRTL_SYS_XATTR_H 1

/* <sys/xattr.h> -- extended attributes.

   ALL TWELVE, NOT THE TWO THAT WERE ASKED FOR. busybox's miscutils/setfattr.c
   uses exactly setxattr, lsetxattr, removexattr and lremovexattr, but the set
   is a THREE-BY-FOUR GRID -- {get,set,list,remove} crossed with
   {path, path-no-follow, fd} -- and half a grid is the shape that gets one arm
   quietly forgotten. They are one syscall family, one file, one commit.

   THE l AND f PREFIXES ARE NOT CONVENIENCES. `lsetxattr' does not follow a
   final symlink and `fsetxattr' takes a descriptor; setfattr's -h option is
   exactly that choice, so an implementation that aliased the three would
   silently write the attribute onto the link target instead of the link. That
   is a wrong ANSWER, not a missing feature, which is why each is its own
   syscall here rather than a wrapper around one of the others.

   THE SIZE PROTOCOL. get/list called with size 0 return the length the buffer
   would need and write nothing -- that is the documented way to size a buffer,
   and it means a 0 return is not always an error. Callers loop; crtl does not
   loop for them.

   Found attempting busybox on i386, where there is no host header to fall back
   on. On x86-64 setfattr.c "passed" by compiling against glibc's copy through
   the host-header fallback, which is the whole subject of
   bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS. */

#include <stddef.h>
#include <sys/types.h>

/* Flags for the set family. Neither means "create or replace" -- 0 does. */
#define XATTR_CREATE  1   /* fail with EEXIST if the attribute exists */
#define XATTR_REPLACE 2   /* fail with ENODATA if it does not */

int setxattr(const char *path, const char *name, const void *value, size_t size, int flags);
int lsetxattr(const char *path, const char *name, const void *value, size_t size, int flags);
int fsetxattr(int fd, const char *name, const void *value, size_t size, int flags);

ssize_t getxattr(const char *path, const char *name, void *value, size_t size);
ssize_t lgetxattr(const char *path, const char *name, void *value, size_t size);
ssize_t fgetxattr(int fd, const char *name, void *value, size_t size);

ssize_t listxattr(const char *path, char *list, size_t size);
ssize_t llistxattr(const char *path, char *list, size_t size);
ssize_t flistxattr(int fd, char *list, size_t size);

int removexattr(const char *path, const char *name);
int lremovexattr(const char *path, const char *name);
int fremovexattr(int fd, const char *name);

#endif /* PXX_CRTL_SYS_XATTR_H */
