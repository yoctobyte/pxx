/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/ipc.h> -- the System V IPC common half: key_t, struct
 * ipc_perm, the IPC_* flags and commands, and ftok().
 *
 * IPC_CREAT/IPC_EXCL/IPC_NOWAIT ARE FLAGS AND IPC_RMID/IPC_SET/IPC_STAT ARE
 * COMMANDS, and they do not share a range by accident -- the flags are 01000,
 * 02000, 04000 because the low nine bits of the same int are a PERMISSION
 * MASK. So `shmget(key, size, 0666 | IPC_CREAT)' is one number carrying two
 * meanings, and a command written where a flag belongs (IPC_STAT is 2) reads
 * as permission bits and creates a segment nothing can open.
 *
 * ftok() IS NOT A HASH AND ITS COLLISIONS ARE STRUCTURAL: it packs the low 8
 * bits of proj_id, the low 8 bits of the device minor, and the low 16 bits of
 * the inode. Two files on one filesystem whose inode numbers differ only above
 * bit 16 get the SAME key, and the program then attaches to somebody else's
 * segment. That is POSIX's definition, not an implementation shortcut, and it
 * is why busybox uses a fixed key instead.
 *
 * Found attempting busybox on i386: sysklogd/logread.c and syslogd.c, which
 * share the log buffer through shm and guard it with a semaphore.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_IPC_H
#define _CRTL_SYS_IPC_H

#include <sys/types.h>

typedef int key_t;

/* Mode bits: OR'd into the low nine permission bits -- see the note above. */
#define IPC_CREAT   01000   /* create key if it does not exist */
#define IPC_EXCL    02000   /* fail if key exists */
#define IPC_NOWAIT  04000   /* return error on wait */

/* Control commands for *ctl(). */
#define IPC_RMID  0   /* remove identifier */
#define IPC_SET   1   /* set ipc_perm options */
#define IPC_STAT  2   /* get ipc_perm options */
#define IPC_INFO  3   /* see ipcs(1) */

#define IPC_PRIVATE  ((key_t) 0)

/* THE KERNEL'S ipc64_perm, WHICH IS NOT THE ipc_perm OF ITS OWN NAME. The
   kernel still carries an older 16-bit-uid layout under that name, reached
   only through the ipc() multiplexer's version bits; the direct shmctl/semctl/
   msgctl syscalls always mean this one -- the kernel ORs IPC_64 in itself, so
   a caller must NOT, or the command comes out unrecognised. Declaring the old
   layout here would compile and would read a uid out of the middle of a gid. */
struct ipc_perm {
  key_t          __key;   /* key supplied to *get() */
  uid_t          uid;     /* owner's effective user ID */
  gid_t          gid;     /* owner's effective group ID */
  uid_t          cuid;    /* creator's effective user ID */
  gid_t          cgid;    /* creator's effective group ID */
  mode_t         mode;    /* read/write permission */
  unsigned short __seq;   /* sequence number */
  unsigned short __pad2;
  unsigned long  __glibc_reserved1;
  unsigned long  __glibc_reserved2;
};

key_t ftok(const char *pathname, int proj_id);

#endif
