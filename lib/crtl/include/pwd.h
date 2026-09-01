/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_PWD_H
#define PXX_CRTL_PWD_H 1

#include <sys/types.h>   /* uid_t, gid_t */

/* Field ORDER is glibc's. Unlike `struct tms', nothing outside this program
   fills this one -- crtl parses /etc/passwd itself -- so the layout is not a
   kernel ABI. It still matches glibc, because code does occasionally
   brace-initialise a struct passwd, and an order that merely "has the right
   fields" would compile and assign the wrong ones. */
struct passwd {
  char  *pw_name;
  char  *pw_passwd;
  uid_t  pw_uid;
  gid_t  pw_gid;
  char  *pw_gecos;
  char  *pw_dir;
  char  *pw_shell;
};

/* Both return a pointer to STATIC storage that the next call overwrites, and
   NULL when there is no such user -- the classic non-reentrant contract, which
   is what busybox's libbb/bb_pwd.c expects. */
struct passwd *getpwnam(const char *name);
struct passwd *getpwuid(uid_t uid);

void setpwent(void);
void endpwent(void);
struct passwd *getpwent(void);

#endif
