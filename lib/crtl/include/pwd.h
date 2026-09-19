/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_PWD_H
#define PXX_CRTL_PWD_H 1

#include <sys/types.h>   /* uid_t, gid_t */
#include <stddef.h>      /* size_t, for the _r forms */

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

/* The reentrant forms, which are the IMPLEMENTATION the two above wrap. They
   touch no static: the caller supplies both the struct and the string buffer
   the struct's fields point into.

   Return value is an ERRNO, not -1, and 0 with *result == NULL means "no such
   user" rather than an error -- the POSIX contract, and the reason a caller
   must check *result and not just the return. ERANGE means buf was too small
   for some line in the file; retry with a bigger one. */
int getpwnam_r(const char *name, struct passwd *pwd, char *buf, size_t buflen,
               struct passwd **result);
int getpwuid_r(uid_t uid, struct passwd *pwd, char *buf, size_t buflen,
               struct passwd **result);

void setpwent(void);
void endpwent(void);
struct passwd *getpwent(void);

#endif
