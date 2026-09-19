/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <grp.h> -- struct group and the /etc/group lookups.
 *
 * The lookups were deferred to "whichever corpus target first calls them".
 * That target arrived: a 79-applet busybox userland wants getgrnam, getgrgid
 * and getgrouplist. See src/grp.c for what is and is not implemented -- in
 * particular that there is NO NSS, exactly as in <pwd.h>.
 */
#ifndef _CRTL_GRP_H
#define _CRTL_GRP_H

#include <sys/types.h>
#include <stddef.h>      /* size_t, for the _r forms */

struct group {
  char  *gr_name;    /* group name */
  char  *gr_passwd;  /* group password */
  gid_t  gr_gid;
  char **gr_mem;     /* NULL-terminated member list */
};

/* The returned struct and every string it points at live in ONE static buffer
   and are invalidated by the next call, which is what glibc's non-_r forms
   promise too. */
void          setgrent(void);
void          endgrent(void);
struct group *getgrent(void);
struct group *getgrnam(const char *name);
struct group *getgrgid(gid_t gid);

/* The reentrant forms. They touch no static: the caller supplies the struct
   and the buffer, and unlike the passwd pair the MEMBER POINTER ARRAY is built
   in that buffer too -- so size it for the line PLUS (members+1) pointers.
   ERANGE means it did not fit; 0 with *result == NULL means no such group. */
int getgrnam_r(const char *name, struct group *grp, char *buf, size_t buflen,
               struct group **result);
int getgrgid_r(gid_t gid, struct group *grp, char *buf, size_t buflen,
               struct group **result);

/* *ngroups is the caller's CAPACITY in and the true count out; -1 means the
   count exceeded the capacity, and the count is still written. */
int getgrouplist(const char *user, gid_t group, gid_t *groups, int *ngroups);

#endif
