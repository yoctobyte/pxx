/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <pwd.h> -- struct passwd ONLY. No lookups.
 *
 * The type is here because headers and structs propagate further than calls
 * do: busybox pulls <pwd.h> from include/libbb.h into every translation unit
 * and reaches getpwnam() only inside #if ENABLE_FEATURE_SUID_CONFIG. Code
 * that merely names the type must compile; code that actually looks a user up
 * must not silently get an answer.
 *
 * So there is deliberately no getpwnam/getpwuid/getpwent here. A stub
 * returning NULL would make "root" not exist and every caller take its
 * unknown-user path, which is a WRONG ANSWER rather than a failure -- the
 * expensive kind of bug in this repo. A declaration without a definition is
 * worse still: the ELF writer would emit a DT_NEEDED and glibc would answer
 * on x86-64 while every cross target failed to link (see the note in
 * <sys/resource.h>). Missing the declaration makes the call a compile error
 * that names the function, which is the honest answer.
 *
 * Implementing them means parsing /etc/passwd -- real, self-contained work,
 * and the right time is when a corpus target actually calls them.
 */
#ifndef _CRTL_PWD_H
#define _CRTL_PWD_H

#include <sys/types.h>

struct passwd {
  char  *pw_name;    /* username */
  char  *pw_passwd;  /* password, or "x" when shadowed */
  uid_t  pw_uid;
  gid_t  pw_gid;
  char  *pw_gecos;   /* real name / comment field */
  char  *pw_dir;     /* home directory */
  char  *pw_shell;   /* login shell */
};

#endif
