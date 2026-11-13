/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/prctl.h> -- prctl(2) and the operations the corpus issues.
 *
 * NOT THE WHOLE REGISTRY, on purpose. prctl's first argument is an open-ended
 * enumeration the kernel keeps extending, and a crtl header that tried to
 * mirror all of it would be wrong the week after it was written. What is here
 * is what busybox asks for -- the process name, the no-new-privs bit, the
 * capability bounding set and the ambient set -- plus the values those
 * operations need for their own arguments.
 *
 * prctl IS VARIADIC, as in glibc: `int prctl(int option, ...)`, and the
 * body reads four longs after the option, which is what glibc's wrapper
 * hands the kernel. Callers pass however many the option needs: dropbear's
 * svr-main.c calls prctl(PR_SET_NAME, name, 0, 0), four arguments. This
 * header used to declare five FIXED longs, on the theory that a variadic
 * declaration "would buy nothing a caller can see". On x86-64 the short call
 * compiled with no diagnostic. On aarch64, i386 and arm32 the call
 * marshalling counts arguments against the prototype and refused it.
 *
 * Found attempting busybox on i386: libbb/vfork_daemon_rexec.c (PR_SET_NAME)
 * and util-linux/setpriv.c (the capability and no-new-privs operations).
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_PRCTL_H
#define _CRTL_SYS_PRCTL_H

#define PR_SET_PDEATHSIG        1
#define PR_GET_PDEATHSIG        2
#define PR_GET_DUMPABLE         3
#define PR_SET_DUMPABLE         4
#define PR_SET_NAME            15
#define PR_GET_NAME            16
#define PR_GET_SECCOMP         21
#define PR_SET_SECCOMP         22
#define PR_CAPBSET_READ        23
#define PR_CAPBSET_DROP        24
#define PR_GET_SECUREBITS      27
#define PR_SET_SECUREBITS      28
#define PR_SET_TIMERSLACK      29
#define PR_GET_TIMERSLACK      30
#define PR_SET_CHILD_SUBREAPER 36
#define PR_GET_CHILD_SUBREAPER 37
#define PR_SET_NO_NEW_PRIVS    38
#define PR_GET_NO_NEW_PRIVS    39

/* The ambient capability set: one option with a sub-command in arg2. */
#define PR_CAP_AMBIENT            47
#define PR_CAP_AMBIENT_IS_SET      1
#define PR_CAP_AMBIENT_RAISE       2
#define PR_CAP_AMBIENT_LOWER       3
#define PR_CAP_AMBIENT_CLEAR_ALL   4

int prctl(int option, ...);

#endif
