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

/* *ngroups is the caller's CAPACITY in and the true count out; -1 means the
   count exceeded the capacity, and the count is still written. */
int getgrouplist(const char *user, gid_t group, gid_t *groups, int *ngroups);

#endif
