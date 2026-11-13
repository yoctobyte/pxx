/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <shadow.h> -- /etc/shadow lookups.
 *
 * Found building dropbear (feature-c-dropbear-builds-with-pxx).
 * common-session.c's fill_passwd() calls getspnam() on EVERY login, not only
 * for password authentication, to find the real hash when pw_passwd is "x".
 * So this has to work, and it has to fail cleanly: a dropbear that is not
 * running as root cannot open /etc/shadow, and then getspnam returns NULL with
 * errno EACCES, as glibc's does.
 *
 * Member order and types are glibc's (sizeof 72 on x86-64, measured).
 * Numeric fields that are EMPTY in the file are -1, which is how shadow(5)
 * spells "not set" and what glibc returns.
 */
#ifndef _CRTL_SHADOW_H
#define _CRTL_SHADOW_H

#include <stdio.h>
#include <stddef.h>

#define SHADOW "/etc/shadow"

struct spwd {
  char *sp_namp;            /* login name */
  char *sp_pwdp;            /* hashed password */
  long int sp_lstchg;       /* days since the epoch of the last change */
  long int sp_min;
  long int sp_max;
  long int sp_warn;
  long int sp_inact;
  long int sp_expire;
  unsigned long int sp_flag;
};

void setspent(void);
void endspent(void);
struct spwd *getspent(void);
struct spwd *getspnam(const char *name);
struct spwd *sgetspent(const char *s);
int getspnam_r(const char *name, struct spwd *spbuf, char *buf, size_t buflen,
               struct spwd **result);

#endif
