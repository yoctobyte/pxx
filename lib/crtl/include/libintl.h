/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <libintl.h> -- GNU gettext's message-catalogue calls, with no
 * catalogues. Every lookup answers the message it was given (ngettext picks
 * the singular or plural by n), which is exactly what glibc answers when no
 * .mo file is installed for the locale: a program built against gettext runs
 * in English. textdomain and bindtextdomain remember what they were told and
 * report it back.
 *
 * xload's configure found glibc's gettext and the pxx link then missed it.
 * feature-crtl-runtime-gaps-from-e2fsprogs-util-linux-dosfstools (follow-up)
 */
#ifndef _CRTL_LIBINTL_H
#define _CRTL_LIBINTL_H

char *gettext(const char *msgid);
char *dgettext(const char *domain, const char *msgid);
char *dcgettext(const char *domain, const char *msgid, int category);
char *ngettext(const char *msgid, const char *msgid_plural, unsigned long n);
char *dngettext(const char *domain, const char *msgid, const char *msgid_plural,
                unsigned long n);
char *dcngettext(const char *domain, const char *msgid, const char *msgid_plural,
                 unsigned long n, int category);
char *textdomain(const char *domain);
char *bindtextdomain(const char *domain, const char *dirname);
char *bind_textdomain_codeset(const char *domain, const char *codeset);

#endif
