/* SPDX-License-Identifier: Zlib */
/* SIGRTMIN/SIGRTMAX: a handler installs on both ends of the range and
   SIGRTMIN is delivered (seatd's tests). Row c_sigrt26, as a crtl program
   and as a --system-libs object linked by gcc, against gcc.
   feature-crtl-sigrtmin-and-sigrtmax */
#include <signal.h>
#include <stdio.h>
#include <unistd.h>
static volatile sig_atomic_t got;
static void h(int s){ got = s; }
int main(void){ struct sigaction sa = {0}; sa.sa_handler = h; if (sigaction(SIGRTMIN, &sa, 0)) return 2; if (sigaction(SIGRTMAX, &sa, 0)) return 3; kill(getpid(), SIGRTMIN); printf("%d\n", got == SIGRTMIN && SIGRTMIN < SIGRTMAX && SIGRTMAX == 64); return 0; }
