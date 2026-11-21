/* SPDX-License-Identifier: Zlib */
/*
 * <execinfo.h>: a program's own call stack, glibc's and NetBSD libexecinfo's
 * interface. See src/execinfo.c for how the frames are found and what the
 * symbol strings hold.
 */
#ifndef _EXECINFO_H
#define _EXECINFO_H

int backtrace(void **buffer, int size);
char **backtrace_symbols(void *const *buffer, int size);
void backtrace_symbols_fd(void *const *buffer, int size, int fd);

#endif
