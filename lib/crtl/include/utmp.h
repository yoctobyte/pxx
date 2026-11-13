/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <utmp.h> -- the login-record TYPES.
 *
 * Found building dropbear (feature-c-dropbear-builds-with-pxx): its
 * src/includes.h includes <utmp.h>, <utmpx.h> and <lastlog.h> whenever
 * configure saw them, and on a glibc host it always does. Without these
 * headers pxx fell back to /usr/include/bits/utmp.h and stopped at glibc's
 * internal `__uint32_t'.
 *
 * TYPES ONLY, NO FUNCTIONS. setutent/getutent/pututline and friends are not
 * declared, so a program that calls them fails at compile time and does not
 * quietly link against nothing. dropbear's loginrec.c only reaches them with
 * utmp support configured on, and the dropbear build here configures it off
 * (--disable-utmp and the rest). Add the functions when a target calls them.
 *
 * THE LAYOUT IS A FILE FORMAT. /var/run/utmp and /var/log/wtmp are read by
 * programs that are not this runtime, so struct utmp must match the system's
 * byte for byte. x86-64 is measured against glibc 2.4x on plexus: sizeof 384,
 * ut_pid 4, ut_line 8, ut_id 40, ut_user 44, ut_host 76, ut_exit 332,
 * ut_session 336, ut_tv 340, ut_addr_v6 348. On x86-64 (and i386) glibc keeps
 * 32-bit ut_session and ut_tv so the file is shared with 32-bit programs
 * (__WORDSIZE_TIME64_COMPAT32). Other 64-bit targets use long and a real
 * struct timeval. That second arm is from glibc's bits/utmp.h and has NOT been
 * measured here.
 */
#ifndef _CRTL_UTMP_H
#define _CRTL_UTMP_H

#include <sys/types.h>
#include <sys/time.h>
#include <stdint.h>

#define UT_LINESIZE  32
#define UT_NAMESIZE  32
#define UT_HOSTSIZE  256

#define _PATH_UTMP     "/var/run/utmp"
#define _PATH_WTMP     "/var/log/wtmp"
#define _PATH_LASTLOG  "/var/log/lastlog"
#define UTMP_FILE      _PATH_UTMP
#define UTMP_FILENAME  _PATH_UTMP
#define WTMP_FILE      _PATH_WTMP
#define WTMP_FILENAME  _PATH_WTMP

/* ut_type */
#define EMPTY          0
#define RUN_LVL        1
#define BOOT_TIME      2
#define NEW_TIME       3
#define OLD_TIME       4
#define INIT_PROCESS   5
#define LOGIN_PROCESS  6
#define USER_PROCESS   7
#define DEAD_PROCESS   8
#define ACCOUNTING     9

struct exit_status {
  short int e_termination;
  short int e_exit;
};

#if defined(__x86_64__) || defined(__i386__)
#define _CRTL_UT_TIME32 1
#endif

struct lastlog {
#ifdef _CRTL_UT_TIME32
  int32_t ll_time;
#else
  time_t ll_time;
#endif
  char ll_line[UT_LINESIZE];
  char ll_host[UT_HOSTSIZE];
};

struct utmp {
  short int ut_type;
  pid_t ut_pid;
  char ut_line[UT_LINESIZE];
  char ut_id[4];
  char ut_user[UT_NAMESIZE];
  char ut_host[UT_HOSTSIZE];
  struct exit_status ut_exit;
#ifdef _CRTL_UT_TIME32
  int32_t ut_session;
  struct {
    int32_t tv_sec;
    int32_t tv_usec;
  } ut_tv;
#else
  long int ut_session;
  struct timeval ut_tv;
#endif
  int32_t ut_addr_v6[4];
  char __glibc_reserved[20];
};

#define ut_name  ut_user
#define ut_time  ut_tv.tv_sec
#define ut_xtime ut_tv.tv_sec
#define ut_addr  ut_addr_v6[0]

#endif
