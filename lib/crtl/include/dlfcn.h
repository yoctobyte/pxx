/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <dlfcn.h> -- dlopen/dlsym/dlclose/dlerror.
 *
 * Routed to the PAL loader that Pascal's dynlibs unit uses, so C and Pascal
 * share one policy. In the default libc-free build there is NO loader: dlopen
 * returns NULL and dlerror says why. That is the "optional library
 * unavailable" answer a caller already handles, e.g. sqlite's extension
 * loading. Under -dPXX_DYNLIB_LIBC the PAL wraps libc's real loader, and the
 * binary then links libc.so.6.
 *
 * The mode flags are accepted and not honoured: the PAL takes only a name.
 * Values match glibc so code that tests or combines them compiles unchanged.
 * dlopen(NULL) (the program's own symbols) is refused through dlerror, because
 * a pxx binary has no dynamic symbol table to hand back.
 *
 * Without this header the HOST's <dlfcn.h> was found instead, and it stopped
 * at glibc's `__BEGIN_DECLS` (sqlite3.c without SQLITE_OMIT_LOAD_EXTENSION).
 * bug-c-sqlite-with-threadsafe-stops-at-a-stray-BEGIN_DECLS
 */
#ifndef _CRTL_DLFCN_H
#define _CRTL_DLFCN_H

#define RTLD_LAZY     0x00001
#define RTLD_NOW      0x00002
#define RTLD_NOLOAD   0x00004
#define RTLD_GLOBAL   0x00100
#define RTLD_LOCAL    0
#define RTLD_NODELETE 0x01000

#define RTLD_DEFAULT  ((void *)0)
#define RTLD_NEXT     ((void *)-1l)

void *dlopen(const char *file, int mode);
void *dlsym(void *handle, const char *name);
int   dlclose(void *handle);
char *dlerror(void);

#endif
