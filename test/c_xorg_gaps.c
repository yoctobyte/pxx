/* What stopped pxx compiling Xorg 21.1, libdrm and pixman (Path B on DRM,
   2026-11-25), each against gcc:
   - a cast to a TYPEDEF in a constant expression kept the operand's type:
     `(off_t)1 << 31` folded as an int shift (libdrm's LARGE_OFF_T assertion)
   - __PRETTY_FUNCTION__ / __FUNCTION__ were undeclared (pixman's FUNC)
   - a function-like macro's name ending a line, its `(` on the next
     (Xorg's `DebugF\n    ("...")`)
   - `__builtin_clz (x)` with a space, in a file without <stdlib.h>
   - `typedef enum { A = 1 } F, *FP;` declared only F (libdrm)
   - crtl: memfd_create + F_ADD_SEALS, clock_getres, pthread_sigmask,
     open_memstream (libdrm), pthread_attr_setscope (Xorg's input thread) */
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

typedef long L;
typedef unsigned short U16;
typedef enum { CTX_PRESERVED = 0x01, CTX_2DONLY = 0x02 } CtxFlags, *CtxFlagsPtr;
static int get_flags(CtxFlagsPtr flags) { *flags = 0; *flags |= CTX_2DONLY; return 0; }
#define STATIC_ASSERT(c) do { (void) sizeof(char [1 - 2*!(c)]); } while (0)
#define LARGE_OFF_T ((((off_t) 1 << 31) << 31) - 1 + (((off_t) 1 << 31) << 31))
enum { E1 = ((L)1 << 40) > 0, E2 = (U16)70000, E3 = (int)((L)3000000000 / 2 > 0) };

#define NOTHING(...)            /* */
#define TWICE(x) ((x) * 2)

static int clz_of(unsigned x) { return __builtin_clz (x); }

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
    return 0;
}
