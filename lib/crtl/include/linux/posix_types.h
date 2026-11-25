/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/posix_types.h> -- the __kernel_* types the UAPI headers
 * declare syscall and ioctl arguments with. The kernel's <linux/types.h>
 * includes this, so a uapi header that names only <linux/types.h> still
 * gets them: DRM's <drm/drm.h> (struct drm_version's name_len etc. are
 * __kernel_size_t) stopped pxx here, compiling libdrm and Rainyday's
 * kmstest.c.
 *
 * Widths follow the kernel's asm/posix_types for the target: the `long'
 * ones are the C long (8 bytes on LP64, 4 on ILP32), and size_t's family is
 * `unsigned long' on LP64 and `unsigned int' on ILP32 (posix_types_32.h,
 * asm-generic) -- the same width as long there, but the spelling matters to
 * a compiler comparing pointer types.
 */
#ifndef _CRTL_LINUX_POSIX_TYPES_H
#define _CRTL_LINUX_POSIX_TYPES_H

typedef long          __kernel_long_t;
typedef unsigned long __kernel_ulong_t;

#if defined(__LP64__)
typedef unsigned long __kernel_size_t;
typedef long          __kernel_ssize_t;
typedef long          __kernel_ptrdiff_t;
#else
typedef unsigned int  __kernel_size_t;
typedef int           __kernel_ssize_t;
typedef int           __kernel_ptrdiff_t;
#endif

typedef __kernel_ulong_t __kernel_ino_t;
typedef int           __kernel_pid_t;
typedef unsigned int  __kernel_uid32_t;
typedef unsigned int  __kernel_gid32_t;
typedef unsigned short __kernel_uid16_t;
typedef unsigned short __kernel_gid16_t;
typedef __kernel_long_t __kernel_suseconds_t;
typedef int           __kernel_daddr_t;

/* i386 kept the 16-bit originals (asm/posix_types_32.h); x86-64 has 32-bit
   ones but a 16-bit __kernel_old_uid_t (posix_types_64.h); everyone else
   takes asm-generic's. */
#if defined(__i386__)
typedef unsigned short __kernel_mode_t;
typedef unsigned short __kernel_ipc_pid_t;
typedef unsigned short __kernel_uid_t;
typedef unsigned short __kernel_gid_t;
typedef __kernel_uid_t __kernel_old_uid_t;
typedef __kernel_gid_t __kernel_old_gid_t;
#elif defined(__x86_64__)
typedef unsigned int  __kernel_mode_t;
typedef int           __kernel_ipc_pid_t;
typedef unsigned int  __kernel_uid_t;
typedef unsigned int  __kernel_gid_t;
typedef unsigned short __kernel_old_uid_t;
typedef unsigned short __kernel_old_gid_t;
#else
typedef unsigned int  __kernel_mode_t;
typedef int           __kernel_ipc_pid_t;
typedef unsigned int  __kernel_uid_t;
typedef unsigned int  __kernel_gid_t;
typedef __kernel_uid_t __kernel_old_uid_t;
typedef __kernel_gid_t __kernel_old_gid_t;
#endif

typedef __kernel_long_t __kernel_off_t;
typedef long long     __kernel_loff_t;
typedef __kernel_long_t __kernel_old_time_t;
typedef __kernel_long_t __kernel_time_t;
typedef long long     __kernel_time64_t;
typedef __kernel_long_t __kernel_clock_t;
typedef int           __kernel_timer_t;
typedef int           __kernel_clockid_t;
typedef char *        __kernel_caddr_t;
typedef int           __kernel_key_t;
typedef int           __kernel_mqd_t;

typedef struct {
    int val[2];
} __kernel_fsid_t;

#endif
