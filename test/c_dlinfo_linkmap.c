/* dlinfo(RTLD_DI_LINKMAP) and Dl_info under _GNU_SOURCE, as NetBSD's
   rumpuser_dl.c uses them (rump-pxx g40). Under --system-libs (and gcc) they
   are glibc's: the main program's link map is there. crtl's own runtime has
   no loader, so the expected output is per mode; see the Makefile row.
   bug-c-crtl-dlfcn-lacks-dlinfo-and-rtld-di-linkmap */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <link.h>
#include <stdio.h>

int main(void)
{
    struct link_map *m = 0;
    Dl_info di;
    void *h = dlopen(0, RTLD_NOW);
    int r = h ? dlinfo(h, RTLD_DI_LINKMAP, &m) : -1;
    printf("RTLD_DI_LINKMAP=%d sizeof(Dl_info)=%d\n", RTLD_DI_LINKMAP, (int)sizeof di);
    printf("linkmap %s\n", (r == 0 && m) ? "found" : "none");
    if (r != 0) printf("dlerror %s\n", dlerror() ? "set" : "clear");
    return 0;
}
