/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <utmpx.h> -- POSIX's spelling of <utmp.h>. On Linux the two
 * records are one layout (glibc: sizeof 384 for both on x86-64, measured), so
 * struct utmpx here has the same members in the same places.
 *
 * Types only, no functions. See <utmp.h> for why, and for where the layout
 * comes from.
 */
#ifndef _CRTL_UTMPX_H
#define _CRTL_UTMPX_H

#include <utmp.h>

#define __UT_LINESIZE UT_LINESIZE
#define __UT_NAMESIZE UT_NAMESIZE
#define __UT_HOSTSIZE UT_HOSTSIZE

struct utmpx {
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

#endif
