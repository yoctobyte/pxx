/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/sendfile.h> -- sendfile(2), a copy between two
 * descriptors that the kernel does without the bytes passing through the
 * caller. util-linux's lib/fileutils.c copies a file with it
 * (ul_copy_file) and nearly every libcommon unit includes the header.
 *
 * off_t is `long' here, as glibc's is without _FILE_OFFSET_BITS=64, so this
 * is the plain sendfile system call on every target.
 */
#ifndef _CRTL_SYS_SENDFILE_H
#define _CRTL_SYS_SENDFILE_H
#include <sys/types.h>

ssize_t sendfile(int out_fd, int in_fd, off_t *offset, size_t count);

#endif
