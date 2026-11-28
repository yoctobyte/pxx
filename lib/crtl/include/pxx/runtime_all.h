/* SPDX-License-Identifier: Zlib */
/*
 * pxx: the shared runtime, as one translation unit. Including a crtl header
 * pulls its implementation (lib/crtl/src/<name>.c), so this list -- every
 * header that HAS an implementation -- compiles the whole C runtime, once,
 * into the object pxx --link adds for --shared-runtime objects.
 *
 * KEEP IN STEP WITH lib/crtl/src: a new src/<name>.c needs its header here,
 * or a --shared-runtime program that calls it fails to link (the self-
 * contained default is unaffected). `tools/gen_crtl_map.py --check` (a gate
 * step) checks it.
 */
#ifndef PXX_CRTL_PXX_RUNTIME_ALL_H
#define PXX_CRTL_PXX_RUNTIME_ALL_H 1

#include <arpa/nameser.h>
#include <assert.h>
#include <crypt.h>
#include <ctype.h>
#include <dirent.h>
#include <dlfcn.h>
#include <err.h>
#include <execinfo.h>
#include <fcntl.h>
#include <fenv.h>
#include <fnmatch.h>
#include <glob.h>
#include <grp.h>
#include <iconv.h>
#include <ifaddrs.h>
#include <inttypes.h>
#include <langinfo.h>
#include <libgen.h>
#include <libintl.h>
#include <linux/capability.h>
#include <locale.h>
#include <malloc.h>
#include <math.h>
#include <mntent.h>
#include <net/if.h>
#include <netdb.h>
#include <netinet/ether.h>
#include <netinet/in.h>
#include <poll.h>
#ifdef __PXXRT_THREADSAFE
#include <pthread.h>   /* needs --threadsafe */
#include <semaphore.h>
#include <threads.h>
#endif
#include <pty.h>
#include <pwd.h>
#include <regex.h>
#include <resolv.h>
#include <sched.h>
#include <setjmp.h>
#include <shadow.h>
#include <signal.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/signalfd.h>
#include <sys/file.h>
#include <sys/inotify.h>
#include <sys/io.h>
#include <sys/ioctl.h>
#include <sys/ipc.h>
#include <sys/klog.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/msg.h>
#include <sys/personality.h>
#include <sys/prctl.h>
#include <sys/ptrace.h>
#include <sys/random.h>
#include <sys/reboot.h>
#include <sys/resource.h>
#include <sys/select.h>
#include <sys/sem.h>
#include <sys/sendfile.h>
#include <sys/shm.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/statvfs.h>
#include <sys/swap.h>
#include <sys/sysinfo.h>
#include <sys/time.h>
#include <sys/times.h>
#include <sys/timex.h>
#include <sys/uio.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <syslog.h>
#include <termios.h>
#include <time.h>
#include <ttyent.h>
#include <unistd.h>
#include <utime.h>
#include <utmpx.h>
#include <wchar.h>
#include <uchar.h>
#include <printf.h>
#include <wctype.h>

/* the marker every --shared-runtime object references (see shared_runtime.h) */
char __PXXRT_MARKER = 1;

#endif
