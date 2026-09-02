/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/mount.h> -- mount(2), umount(2), umount2(2) and the MS_
 * flags.
 *
 * The MS_ values are transcribed from this box's linux/mount.h BY SCRIPT
 * rather than by hand; they are a bitmask, so a wrong bit is not rejected --
 * it mounts with a DIFFERENT option and the failure appears later, as a device
 * node that works where nodev was asked for.
 *
 * MS_MGC_VAL IS NOT A FLAG. It is a magic prefix the kernel required before
 * 2.4 and now ignores if the top 16 bits match; busybox still ORs it in.
 * Keeping it in the same namespace as the flags is the kernel's own doing.
 *
 * Found attempting busybox rung 2: util-linux/mount.c, umount.c, switch_root.c.
 */
#ifndef _CRTL_SYS_MOUNT_H
#define _CRTL_SYS_MOUNT_H

#include <sys/ioctl.h>

#define MS_RDONLY        1            /* Mount read-only */
#define MS_NOSUID        2            /* Ignore suid and sgid bits */
#define MS_NODEV         4            /* Disallow access to device special files */
#define MS_NOEXEC        8            /* Disallow program execution */
#define MS_SYNCHRONOUS   16           /* Writes are synced at once */
#define MS_REMOUNT       32           /* Alter flags of a mounted FS */
#define MS_MANDLOCK      64           /* Allow mandatory locks on an FS */
#define MS_DIRSYNC       128          /* Directory modifications are synchronous */
#define MS_NOSYMFOLLOW   256          /* Do not follow symlinks */
#define MS_NOATIME       1024         /* Do not update access times. */
#define MS_NODIRATIME    2048         /* Do not update directory access times */
#define MS_BIND          4096         
#define MS_MOVE          8192         
#define MS_REC           16384        
#define MS_VERBOSE       32768        /* War is peace. Verbosity is silence.
#define MS_SILENT        32768        
#define MS_POSIXACL      (1<<16)      /* VFS does not apply the umask */
#define MS_UNBINDABLE    (1<<17)      /* change to unbindable */
#define MS_PRIVATE       (1<<18)      /* change to private */
#define MS_SLAVE         (1<<19)      /* change to slave */
#define MS_SHARED        (1<<20)      /* change to shared */
#define MS_RELATIME      (1<<21)      /* Update atime relative to mtime/ctime. */
#define MS_KERNMOUNT     (1<<22)      /* this is a kern_mount call */
#define MS_I_VERSION     (1<<23)      /* Update inode I_version field */
#define MS_STRICTATIME   (1<<24)      /* Always perform atime updates */
#define MS_LAZYTIME      (1<<25)      /* Update the on-disk [acm]times lazily */
#define MS_SUBMOUNT      (1<<26)      
#define MS_NOREMOTELOCK  (1<<27)      
#define MS_NOSEC         (1<<28)      
#define MS_BORN          (1<<29)      
#define MS_ACTIVE        (1<<30)      
#define MS_NOUSER        (1<<31)      
#define MS_MGC_VAL       0xC0ED0000   
#define MS_MGC_MSK       0xffff0000   
/* umount2(2)'s flags -- a different namespace from MS_ despite the shared
   call. MNT_FORCE and MNT_DETACH are the two busybox uses. */
#define MNT_FORCE       1
#define MNT_DETACH      2
#define MNT_EXPIRE      4
#define UMOUNT_NOFOLLOW 8

/* Block-device ioctls, from linux/fs.h -- they live here in practice because
   <sys/mount.h> is what a program that resizes or measures a device includes.
   BLKGETSIZE64 writes a u64 (BYTES); BLKGETSIZE writes a long (512-BYTE
   SECTORS). Confusing the two is off by a factor of 512 with no error. */
#define BLKRRPART    _IO(0x12, 95)
#define BLKGETSIZE   _IO(0x12, 96)
#define BLKFLSBUF    _IO(0x12, 97)
#define BLKSSZGET    _IO(0x12, 104)
#define BLKGETSIZE64 _IOR(0x12, 114, size_t)

/* `data' is filesystem-specific and may be NULL; `source' may be NULL for a
   filesystem that needs none (proc, sysfs). 0 or -1/errno. */
int mount(const char *source, const char *target, const char *fstype,
          unsigned long mountflags, const void *data);
/* umount(target) is umount2(target, 0). */
int umount(const char *target);
int umount2(const char *target, int flags);

#endif
