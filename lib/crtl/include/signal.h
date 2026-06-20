#ifndef PXX_CRTL_SIGNAL_H
#define PXX_CRTL_SIGNAL_H 1

typedef int sig_atomic_t;

#define SIG_DFL ((void (*)(int))0)
#define SIG_IGN ((void (*)(int))1)
#define SIG_ERR ((void (*)(int))-1)

#define SIGABRT 6
#define SIGFPE 8
#define SIGILL 4
#define SIGINT 2
#define SIGSEGV 11
#define SIGTERM 15

void (*signal(int sig, void (*func)(int)))(int);
int raise(int sig);

#endif
