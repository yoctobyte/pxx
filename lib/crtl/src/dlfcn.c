/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: dlopen/dlsym/dlclose/dlerror over the PAL loader (see
 * <dlfcn.h>). dlerror follows POSIX: it returns the message for the MOST
 * RECENT failure since the last call and then clears it, so a second call
 * returns NULL. Callers use that to tell "the symbol's value is NULL" from
 * "the lookup failed".
 */
#include <dlfcn.h>

extern void *__pxx_dlopen(const char *name);
extern void *__pxx_dlsym(void *handle, const char *sym);
extern int   __pxx_dlclose(void *handle);
extern int   __pxx_dl_available(void);

static char dl_msg[256];
static int  dl_pending;

/* dl_msg := a + b (b may be NULL), truncated to fit. */
static void dl_fail(const char *a, const char *b)
{
    int n = 0;
    while (*a && n < (int)sizeof dl_msg - 1) dl_msg[n++] = *a++;
    if (b)
        while (*b && n < (int)sizeof dl_msg - 1) dl_msg[n++] = *b++;
    dl_msg[n] = 0;
    dl_pending = 1;
}

static const char *const dl_noloader =
    "dynamic loading is not available: this pxx build has no loader "
    "(the libc-free runtime; build with -dPXX_DYNLIB_LIBC for one)";

void *dlopen(const char *file, int mode)
{
    void *h;
    (void)mode;
    if (!__pxx_dl_available()) { dl_fail(dl_noloader, 0); return 0; }
    if (!file) {
        dl_fail("dlopen(NULL): a pxx binary has no dynamic symbol table to return", 0);
        return 0;
    }
    h = __pxx_dlopen(file);
    if (!h) dl_fail("cannot load shared object: ", file);
    return h;
}

void *dlsym(void *handle, const char *name)
{
    void *p;
    if (!__pxx_dl_available()) { dl_fail(dl_noloader, 0); return 0; }
    if (!handle) { dl_fail("dlsym: no handle for ", name); return 0; }
    p = __pxx_dlsym(handle, name);
    if (!p) dl_fail("undefined symbol: ", name);
    return p;
}

int dlclose(void *handle)
{
    if (!__pxx_dl_available()) { dl_fail(dl_noloader, 0); return -1; }
    if (__pxx_dlclose(handle) != 0) { dl_fail("dlclose failed", 0); return -1; }
    return 0;
}

char *dlerror(void)
{
    if (!dl_pending) return 0;
    dl_pending = 0;
    return dl_msg;
}
