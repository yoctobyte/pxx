/* SPDX-License-Identifier: MPL-2.0 */
/* Minimal libdl import surface for the dlopen/dlsym interop test —
   project-owned declarations of the standard POSIX dl API subset the test
   uses (see test_c_dlopen.pas). Replaces a former symlink to the system
   dlfcn.h, which broke on checkouts without glibc headers. */
#ifndef PXX_TEST_DL_H
#define PXX_TEST_DL_H

#define RTLD_LAZY 1
#define RTLD_NOW  2

extern void *dlopen(const char *file, int mode);
extern void *dlsym(void *handle, const char *name);
extern int   dlclose(void *handle);
extern char *dlerror(void);

#endif
