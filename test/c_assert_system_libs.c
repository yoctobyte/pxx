/* <assert.h> under --system-libs binds to the libc's __assert_fail: crtl's
   __pxx_assert_fail body is not pulled on that path and no libc exports it
   (NetBSD rumpuser sp.c/bio.c). bug-c-assert-under-system-libs-imports-pxx-assert-fail */
#include <assert.h>
#include <stdio.h>
int main(int argc, char **argv) { (void)argv; assert(argc == 1); puts("assert passed"); return 0; }
