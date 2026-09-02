/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/personality.h> -- personality(2).
 *
 * PER_LINUX32 IS NOT "RUN A 32-BIT BINARY". It changes what uname(2) reports
 * and where mmap places things; setarch uses it to make a build system that
 * greps `uname -m' believe it is on i686.
 *
 * THE PERSONALITY PROPER IS THE LOW BYTE AND THE REST ARE FLAGS OR'D ON TOP,
 * and several of the named personalities below already carry flags -- PER_SVR4
 * is not 0x0001, it is 0x0001 with STICKY_TIMEOUTS and MMAP_PAGE_ZERO folded
 * in. Writing the low byte alone compiles, runs, and silently gives a
 * different personality, so these are transcribed whole from glibc rather than
 * summarised. Every one below is `& PER_MASK'-equal to its number and no more
 * than that.
 *
 * glibc spells these as an enum; macros are the same values and additionally
 * answer #ifdef, which is how portable code tests for PER_LINUX32.
 *
 * Found attempting busybox on i386: util-linux/setarch.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_PERSONALITY_H
#define _CRTL_SYS_PERSONALITY_H

/* Flags. These occupy the top three bytes. */
#define UNAME26             0x0020000
#define ADDR_NO_RANDOMIZE   0x0040000
#define FDPIC_FUNCPTRS      0x0080000
#define MMAP_PAGE_ZERO      0x0100000
#define ADDR_COMPAT_LAYOUT  0x0200000
#define READ_IMPLIES_EXEC   0x0400000
#define ADDR_LIMIT_32BIT    0x0800000
#define SHORT_INODE         0x1000000
#define WHOLE_SECONDS       0x2000000
#define STICKY_TIMEOUTS     0x4000000
#define ADDR_LIMIT_3GB      0x8000000

/* Personalities. These go in the low byte; the top bit is avoided because it
   would collide with an error return. */
#define PER_LINUX        0x0000
#define PER_LINUX_32BIT  (0x0000 | ADDR_LIMIT_32BIT)
#define PER_LINUX_FDPIC  (0x0000 | FDPIC_FUNCPTRS)
#define PER_SVR4         (0x0001 | STICKY_TIMEOUTS | MMAP_PAGE_ZERO)
#define PER_SVR3         (0x0002 | STICKY_TIMEOUTS | SHORT_INODE)
#define PER_SCOSVR3      (0x0003 | STICKY_TIMEOUTS | WHOLE_SECONDS | SHORT_INODE)
#define PER_OSR5         (0x0003 | STICKY_TIMEOUTS | WHOLE_SECONDS)
#define PER_WYSEV386     (0x0004 | STICKY_TIMEOUTS | SHORT_INODE)
#define PER_ISCR4        (0x0005 | STICKY_TIMEOUTS)
#define PER_BSD          0x0006
#define PER_SUNOS        (0x0006 | STICKY_TIMEOUTS)
#define PER_XENIX        (0x0007 | STICKY_TIMEOUTS | SHORT_INODE)
#define PER_LINUX32      0x0008
#define PER_LINUX32_3GB  (0x0008 | ADDR_LIMIT_3GB)
#define PER_IRIX32       (0x0009 | STICKY_TIMEOUTS)   /* IRIX5 32-bit */
#define PER_IRIXN32      (0x000a | STICKY_TIMEOUTS)   /* IRIX6 new 32-bit */
#define PER_IRIX64       (0x000b | STICKY_TIMEOUTS)   /* IRIX6 64-bit */
#define PER_RISCOS       0x000c
#define PER_SOLARIS      (0x000d | STICKY_TIMEOUTS)
#define PER_UW7          (0x000e | STICKY_TIMEOUTS | MMAP_PAGE_ZERO)
#define PER_OSF4         0x000f
#define PER_HPUX         0x0010
#define PER_MASK         0x00ff

int personality(unsigned long persona);

#endif
