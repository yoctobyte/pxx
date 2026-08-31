/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <grp.h> -- struct group ONLY. No lookups.
 *
 * Same reasoning as <pwd.h>, which see: the type travels with the headers,
 * the calls do not, and a stub that reports "no such group" would be a wrong
 * answer rather than a failure. Implementing getgrnam/getgrgid means parsing
 * /etc/group and belongs to whichever corpus target first calls them.
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

#endif
