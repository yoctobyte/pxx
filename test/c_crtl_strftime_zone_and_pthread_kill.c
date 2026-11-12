/* Two crtl gaps a busybox userland hit (Gibux, 2026-11-13), output is gcc's:
   - strftime had only the subset Lua's os.date emits: `date' printed a literal
     "%Z", and %z %T %D %F %R %r %c %x %X %C %u %U %W %k %l %P %n %t %s were
     missing; %e was not space-padded.
   - pthread_kill did not exist ("call to undeclared function"). A pxx
     pthread_t is the kernel tid, so it is tgkill(getpid(), tid, sig).
   Built with --threadsafe. */
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <signal.h>
#include <errno.h>
#include <pthread.h>

static volatile sig_atomic_t got;
static void on_usr1(int sig) { got = sig; }

static void show(const char *f, const struct tm *tm)
{
    char b[128];
    size_t n = strftime(b, sizeof b, f, tm);
    printf("[%s] %zu \"%s\"\n", f, n, b);
}

int main(void)
{
    time_t t = 1700000008;          /* 2023-11-14 22:13:28 UTC, a Tuesday */
    struct tm g = *gmtime(&t);
    const char *fmts[] = { "%a %b %e %H:%M:%S %Z %Y", "%z", "%T", "%D", "%F",
                           "%R", "%r", "%c", "%x", "%X", "%C", "%u %w", "%U %W %j",
                           "%k|%l|%P|%p", "a%nb%tc", "%s", "%%", 0 };
    for (int i = 0; fmts[i]; i++)
        show(fmts[i], &g);

    /* a zone east of UTC, set by hand: %z, %Z and %s read the struct tm */
    struct tm e = g;
    e.tm_hour = 0; e.tm_mday = 15; e.tm_wday = 3; e.tm_yday = 318;
    e.tm_gmtoff = 7200;
    e.tm_zone = "CEST";
    show("%F %T %z %Z %s", &e);
    e.tm_mday = 3;                  /* %e pads with a space */
    show("[%e] [%d]", &e);

    char small[4];
    printf("trunc %zu\n", strftime(small, sizeof small, "%T", &g));

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_usr1;
    sigaction(SIGUSR1, &sa, 0);
    printf("kill0 %d\n", pthread_kill(pthread_self(), 0));
    printf("kill %d got %d\n", pthread_kill(pthread_self(), SIGUSR1), (int)got);
    printf("bad %d\n", pthread_kill(pthread_self(), 999) == EINVAL);
    return 0;
}
