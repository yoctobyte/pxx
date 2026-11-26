/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <ttyent.h> -- the BSD terminal table, /etc/ttys.
 *
 * One entry per line: a device name, the command run on it, the terminal
 * type, then flags (`on', `off', `secure', `window=CMD'); a field may be
 * double-quoted to hold blanks, with \" for a quote, and `#' starts a
 * comment. A Linux system normally has no /etc/ttys at all, and then every
 * lookup answers NULL, which is what util-linux's lib/ttyutils.c expects
 * when it asks getttynam() for a terminal's default TERM.
 */
#ifndef _CRTL_TTYENT_H
#define _CRTL_TTYENT_H

#define _PATH_TTYS "/etc/ttys"

#define _TTYS_OFF     "off"
#define _TTYS_ON      "on"
#define _TTYS_SECURE  "secure"
#define _TTYS_WINDOW  "window"

struct ttyent {
  char *ty_name;      /* the device, without /dev/ */
  char *ty_getty;     /* the command to run on it */
  char *ty_type;      /* its terminal type */
#define TTY_ON     0x01   /* enable logins (start ty_getty) */
#define TTY_SECURE 0x02   /* allow uid 0 to log in */
  int ty_status;
  char *ty_window;    /* the command that starts a window manager */
  char *ty_comment;
};

struct ttyent *getttyent(void);
struct ttyent *getttynam(const char *tty);
int setttyent(void);
int endttyent(void);

#endif
