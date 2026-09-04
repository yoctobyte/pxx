/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_INOTIFY_H
#define PXX_CRTL_SYS_INOTIFY_H 1

/* <sys/inotify.h> -- filesystem event notification.

   THE EVENT RECORD IS A WIRE FORMAT read out of a file descriptor, and its
   trailing name is a FLEXIBLE ARRAY -- so `sizeof(struct inotify_event)' is
   the header alone, and a reader walks the buffer by
   `sizeof(struct inotify_event) + ie->len'. busybox's miscutils/inotifyd.c
   does exactly that at line 215. Add a field and every consumer misparses the
   stream silently, so this struct is the kernel's and nothing else.

   inotify_init() vs inotify_init1(): the asm-generic targets (aarch64,
   riscv32) HAVE NO SYS_inotify_init AT ALL -- the table starts at init1 -- so
   this file provides init as init1(0) there, which is what glibc does on the
   same targets. That is a real difference between the arms and not a
   simplification: without it, inotifyd would take the ENOSYS arm on two of the
   five targets while working on the other three, which is the exact shape of
   the arm32 syscall-table bug this runtime spent a day on.

   IN_CLOEXEC and IN_NONBLOCK are O_CLOEXEC and O_NONBLOCK, spelled through
   <fcntl.h> rather than repeated -- and <fcntl.h> is where the note lives
   about which open flags are NOT uniform across targets. These two are.

   Found attempting busybox on i386, where there is no host header to fall back
   on. */

#include <stdint.h>
#include <fcntl.h>

struct inotify_event {
  int32_t  wd;      /* the watch this event is for */
  uint32_t mask;    /* the IN_* bits that fired */
  uint32_t cookie;  /* pairs an IN_MOVED_FROM with its IN_MOVED_TO */
  uint32_t len;     /* bytes of `name', including padding NULs; may be 0 */
  char     name[];  /* present only when len > 0 */
};

/* Events a watch can report. */
#define IN_ACCESS        0x00000001  /* file was read */
#define IN_MODIFY        0x00000002  /* file was written */
#define IN_ATTRIB        0x00000004  /* metadata changed */
#define IN_CLOSE_WRITE   0x00000008  /* writable file closed */
#define IN_CLOSE_NOWRITE 0x00000010  /* unwritable file closed */
#define IN_OPEN          0x00000020  /* file was opened */
#define IN_MOVED_FROM    0x00000040  /* moved out of a watched directory */
#define IN_MOVED_TO      0x00000080  /* moved into one */
#define IN_CREATE        0x00000100  /* created in a watched directory */
#define IN_DELETE        0x00000200  /* deleted from one */
#define IN_DELETE_SELF   0x00000400  /* the watched object itself was deleted */
#define IN_MOVE_SELF     0x00000800  /* the watched object itself was moved */

#define IN_CLOSE         (IN_CLOSE_WRITE | IN_CLOSE_NOWRITE)
#define IN_MOVE          (IN_MOVED_FROM | IN_MOVED_TO)

/* Sent by the kernel, never asked for. */
#define IN_UNMOUNT       0x00002000  /* the backing filesystem went away */
#define IN_Q_OVERFLOW    0x00004000  /* the queue overflowed; wd is -1 */
#define IN_IGNORED       0x00008000  /* the watch was removed */
#define IN_ISDIR         0x40000000  /* or-ed into mask: the subject is a dir */

/* Or-ed into the mask given to inotify_add_watch. */
#define IN_ONLYDIR       0x01000000  /* fail unless the path is a directory */
#define IN_DONT_FOLLOW   0x02000000  /* do not follow a final symlink */
#define IN_EXCL_UNLINK   0x04000000  /* stop reporting once unlinked */
#define IN_MASK_CREATE   0x10000000  /* fail if a watch already exists */
#define IN_MASK_ADD      0x20000000  /* add to an existing watch's mask */
#define IN_ONESHOT       0x80000000  /* remove the watch after one event */

#define IN_ALL_EVENTS \
  (IN_ACCESS | IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_CLOSE_NOWRITE | \
   IN_OPEN | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE | \
   IN_DELETE_SELF | IN_MOVE_SELF)

/* Flags for inotify_init1. Same bits as the open flags they are named for. */
#define IN_CLOEXEC  O_CLOEXEC
#define IN_NONBLOCK O_NONBLOCK

int inotify_init(void);
int inotify_init1(int flags);
int inotify_add_watch(int fd, const char *pathname, uint32_t mask);
int inotify_rm_watch(int fd, int wd);

#endif /* PXX_CRTL_SYS_INOTIFY_H */
