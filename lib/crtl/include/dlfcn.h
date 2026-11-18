/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <dlfcn.h> -- dlopen/dlsym/dlclose/dlerror.
 *
 * Routed to the PAL loader that Pascal's dynlibs unit uses, so C and Pascal
 * share one policy. In the default libc-free build there is NO loader: dlopen
 * returns NULL and dlerror says why. That is the "optional library
 * unavailable" answer a caller already handles, e.g. sqlite's extension
 * loading. Under -dPXX_DYNLIB_LIBC the PAL wraps libc's real loader, and the
 * binary then links libc.so.6. Under --os=nt the PAL uses Windows' loader
 * (LoadLibraryA, GetProcAddress, FreeLibrary). dlsym's address is
 * GetProcAddress's; a call through a function pointer that lies outside the
 * program's code takes the Microsoft convention (docs/targets/windows.md).
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

/* GNU extensions, under _GNU_SOURCE as glibc declares them: NetBSD's
 * rumpuser_dl.c walks the link map with dlinfo(RTLD_DI_LINKMAP). Under
 * --system-libs these are glibc's own; in crtl's libc-free runtime there is no
 * link map to hand back, so dlinfo fails through dlerror and dladdr finds
 * nothing (0), which is the "no information" answer both already have.
 * Request values and Dl_info's layout match glibc. rump-pxx g40 */
/* Outside the main guard, with its own: crtl's runtime is one translation
 * unit, so an earlier plain #include <dlfcn.h> must not hide this section from
 * a later one under _GNU_SOURCE. */
#if defined(_GNU_SOURCE) && !defined(_CRTL_DLFCN_GNU)
#define _CRTL_DLFCN_GNU
#define RTLD_DI_LMID        1
#define RTLD_DI_LINKMAP     2
#define RTLD_DI_CONFIGADDR  3
#define RTLD_DI_SERINFO     4
#define RTLD_DI_SERINFOSIZE 5
#define RTLD_DI_ORIGIN      6
#define RTLD_DI_PROFILENAME 7
#define RTLD_DI_PROFILEOUT  8
#define RTLD_DI_TLS_MODID   9
#define RTLD_DI_TLS_DATA    10

typedef struct {
    const char *dli_fname;   /* the object containing the address */
    void       *dli_fbase;   /* its load base */
    const char *dli_sname;   /* the nearest symbol */
    void       *dli_saddr;   /* that symbol's address */
} Dl_info;

int dlinfo(void *handle, int request, void *arg);
int dladdr(const void *addr, Dl_info *info);
#endif
