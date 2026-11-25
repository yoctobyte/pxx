/* What stopped pxx compiling Xorg 21.1, libdrm and pixman (Path B on DRM,
   2026-11-25), each against gcc:
   - a cast to a TYPEDEF in a constant expression kept the operand's type:
     `(off_t)1 << 31` folded as an int shift (libdrm's LARGE_OFF_T assertion)
   - __PRETTY_FUNCTION__ / __FUNCTION__ were undeclared (pixman's FUNC)
   - a function-like macro's name ending a line, its `(` on the next
     (Xorg's `DebugF\n    ("...")`)
   - `__builtin_clz (x)` with a space, in a file without <stdlib.h>
   - `typedef enum { A = 1 } F, *FP;` declared only F (libdrm)
   - `sizeof((arr))` sized the decayed pointer, so ARRAY_SIZE written as
     `sizeof((a)) / sizeof((a)[0])` was 1 (Xorg's modesetting)
   - crtl: memfd_create + F_ADD_SEALS, clock_getres, pthread_sigmask,
     open_memstream (libdrm), pthread_attr_setscope (Xorg's input thread),
     epoll (os/ospoll.c), iopl/ioperm (<sys/io.h>), backtrace */
#define _GNU_SOURCE
#include <stdio.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <time.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <stddef.h>
#include <errno.h>
#include <sys/epoll.h>
#include <sys/io.h>
#include <execinfo.h>

typedef long L;
typedef unsigned short U16;
typedef enum { CTX_PRESERVED = 0x01, CTX_2DONLY = 0x02 } CtxFlags, *CtxFlagsPtr;
static int get_flags(CtxFlagsPtr flags) { *flags = 0; *flags |= CTX_2DONLY; return 0; }
#define STATIC_ASSERT(c) do { (void) sizeof(char [1 - 2*!(c)]); } while (0)
#define LARGE_OFF_T ((((off_t) 1 << 31) << 31) - 1 + (((off_t) 1 << 31) << 31))
enum { E1 = ((L)1 << 40) > 0, E2 = (U16)70000, E3 = (int)((L)3000000000 / 2 > 0) };

#define NOTHING(...)            /* */
#define TWICE(x) ((x) * 2)

#define ARRAY_SIZE(a) (sizeof((a)) / sizeof((a)[0]))
static const char *const output_names[] = { "None", "VGA", "DVI-I", "DVI-D", "DVI-A",
    "Composite", "SVIDEO", "LVDS", "Component", "DIN", "DP", "HDMI", "HDMI-B", "TV", "eDP",
    "Virtual", "DSI", "DPI", };
static int arr12[3];
/* sizeof((expr)) inside a static initialiser: the first fix removed the
   redundant pair from the token stream, which moved the initialiser's
   recorded token positions (xload's `sizeof(XtRString)`) */
static const char res_strs[] = "BooleanString";
#define RES_STR ((const char *)&res_strs[7])
typedef struct { const char *n; unsigned sz; int v; } ResRec;
static ResRec res_tab[] = {
    { "a", sizeof(int), 1 },
    { "b", sizeof(RES_STR), 2 },
    { "c", sizeof((res_strs)), 3 },
};

static int clz_of(unsigned x) { return __builtin_clz (x); }

/* an element of an array of pointers is a pointer to the element type, and its
   arithmetic steps by that type (xkmread.c: `type[g] - &map->types[0]`) */
typedef struct { long a[5]; } KType;
static KType ktypes[8];
static KType *gkt[4];
struct KMap { KType *f[4]; int *g[2]; };

static void who(const char *f, const char *what) { printf("%s %s\n", f, what); }

int main(void)
{
    struct timespec r;
    sigset_t s, old;
    int fd;

    STATIC_ASSERT(LARGE_OFF_T % 2147483629 == 721 && LARGE_OFF_T % 2147483647 == 1);
    printf("enum %d %d %d\n", E1, E2, E3);
    who(__func__, "func");
    who(__FUNCTION__, "FUNCTION");
    who((const char *) (__PRETTY_FUNCTION__), "PRETTY");
    NOTHING
        ("skipped %d\n", 1);
    printf("twice %d\n", TWICE
           (21));
    printf("clz %d %d\n", clz_of(1), clz_of(0x80000000u));
    {
        int loc[7];
        unsigned type = 15;
        printf("sizeof %d %d %d %d %d", (int)ARRAY_SIZE(output_names), (int)sizeof(((arr12))),
               (int)sizeof((loc)), (int)ARRAY_SIZE(loc), (int)sizeof((loc)[0]));
        printf(" %s\n", type >= ARRAY_SIZE(output_names) ? "Unknown" : output_names[type]);
        printf("res %s %u %d %s %u %d %s %u %d\n", res_tab[0].n, res_tab[0].sz, res_tab[0].v,
               res_tab[1].n, res_tab[1].sz, res_tab[1].v, res_tab[2].n, res_tab[2].sz, res_tab[2].v);
    }
    {
        CtxFlags cf = CTX_PRESERVED;
        get_flags(&cf);
        printf("enum typedef ptr %d\n", (int)cf);
    }

    fd = memfd_create("t", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    printf("memfd %s", fd >= 0 ? "ok" : "fail");
    if (fd >= 0) {
        printf(" seal %d", fcntl(fd, F_ADD_SEALS, F_SEAL_SHRINK));
        printf(" seals %d", fcntl(fd, F_GET_SEALS));
        close(fd);
    }
    printf("\n");
    printf("getres %d", clock_getres(CLOCK_MONOTONIC, &r));
    printf(" %d\n", r.tv_sec == 0 && r.tv_nsec > 0 && r.tv_nsec <= 1000000);

    sigemptyset(&s);
    sigaddset(&s, SIGUSR1);
    printf("block %d", pthread_sigmask(SIG_BLOCK, &s, NULL));
    printf(" get %d", pthread_sigmask(SIG_BLOCK, NULL, &old));
    printf(" member %d", sigismember(&old, SIGUSR1));
    printf(" bad %d\n", pthread_sigmask(12345, &s, NULL));

    {
        char *buf = NULL;
        size_t len = 99;
        FILE *m = open_memstream(&buf, &len);
        int i;
        printf("memstream %d", m != NULL);
        fflush(m);
        printf(" empty %d [%s]", (int)len, buf ? buf : "(null)");
        fprintf(m, "AFBC(%s,%d)", "BLOCK_32x8", 42);
        fputc('|', m);
        fputs("SPLIT", m);
        fwrite("_YTR", 1, 4, m);
        for (i = 0; i < 300; i++) fprintf(m, "%c", 'a' + i % 26);
        fclose(m);
        printf(" len %d head [%.30s] tail [%s] nul %d\n", (int)len, buf, buf + len - 5,
               buf[len] == 0);
        free(buf);
    }
    {
        pthread_attr_t a;
        int sc = -1;
        pthread_attr_init(&a);
        printf("scope %d", pthread_attr_setscope(&a, PTHREAD_SCOPE_SYSTEM));
        printf(" %d", pthread_attr_setscope(&a, PTHREAD_SCOPE_PROCESS));
        pthread_attr_getscope(&a, &sc);
        printf(" get %d\n", sc);
        pthread_attr_destroy(&a);
    }
    {
        struct epoll_event ev, out[4];
        int ep = epoll_create1(EPOLL_CLOEXEC), p[2], n;
        printf("epoll size %d off %d", (int)sizeof(struct epoll_event),
               (int)offsetof(struct epoll_event, data));
        if (ep >= 0 && pipe(p) == 0) {
            ev.events = EPOLLIN;
            ev.data.u64 = 0x1122334455667788ULL;
            printf(" ctl %d", epoll_ctl(ep, EPOLL_CTL_ADD, p[0], &ev));
            printf(" idle %d", epoll_wait(ep, out, 4, 0));
            n = (int)write(p[1], "x", 1);
            n = epoll_wait(ep, out, 4, 1000);
            printf(" ready %d %d %d", n, out[0].events == EPOLLIN,
                   out[0].data.u64 == 0x1122334455667788ULL);
            close(p[0]); close(p[1]); close(ep);
        }
        printf(" bad %d", epoll_create(0));
        printf("\n");
    }
    {
        void *bt[8];
        errno = 0;
        printf("iopl %d", geteuid() == 0 ? -1 : iopl(3));
        printf(" ioperm %d", geteuid() == 0 ? -1 : ioperm(0x3c0, 32, 1));
        printf(" backtrace %d\n", backtrace(bt, 8) > 0);
    }
    {
        KType *type[4]; int iv[10], *ia[2]; char *cs[3], **ca[2];
        struct KMap km, *pkm = &km; unsigned char kt[2];
        type[0] = &ktypes[2]; type[1] = &ktypes[5]; gkt[1] = &ktypes[6];
        km.f[1] = &ktypes[4]; km.g[1] = &iv[7]; ia[1] = &iv[6]; ca[1] = &cs[2];
        kt[0] = type[0] - (&ktypes[0]);
        kt[1] = type[1] - &ktypes[0];
        printf("ptr-array %u %u %ld %ld %ld %ld", kt[0], kt[1], (long)(gkt[1] - ktypes),
               (long)(km.f[1] - ktypes), (long)(pkm->f[1] - ktypes), (long)(km.g[1] - iv));
        printf(" %ld %ld %ld %ld %ld", (long)((ia[1] + 1) - iv), (long)(ca[1] - cs),
               (long)(*(type + 1) - ktypes), (long)(*type - ktypes), (long)(++type[1] - ktypes));
        printf(" %d\n", (type[1] + 1)->a == ktypes[7].a);
    }
    {
        /* %i takes the base from the prefix, as strtol(…, 0) does (xkbcomp's
           Private(type=0x86) became NoAction) */
        int a = -1, b = -1, c = -1, d = -1, n;
        unsigned x = 0;
        n = sscanf("0x86 017 -0X1f 42", "%i %i %i %i", &a, &b, &c, &d);
        printf("scanf-i %d %d %d %d %d", n, a, b, c, d);
        n = sscanf("0x1fz", "%x", &x);
        printf(" %d %u\n", n, x);
    }
    return 0;
}
