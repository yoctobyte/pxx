/* SPDX-License-Identifier: Zlib */
/* C runtime: <libintl.h> without catalogues -- see the header. */
#include <libintl.h>
#include <string.h>

static char crtl_intl_domain[64] = "messages";
static char crtl_intl_dir[256];
static char crtl_intl_codeset[32];

static char *crtl_intl_keep(char *slot, unsigned long size, const char *s)
{
  if (s) {
    strncpy(slot, s, size - 1);
    slot[size - 1] = 0;
  }
  return slot;
}

char *gettext(const char *msgid) { return (char *)msgid; }
char *dgettext(const char *domain, const char *msgid) { (void)domain; return (char *)msgid; }
char *dcgettext(const char *domain, const char *msgid, int category)
{
  (void)domain; (void)category;
  return (char *)msgid;
}
char *ngettext(const char *msgid, const char *msgid_plural, unsigned long n)
{
  return (char *)(n == 1 ? msgid : msgid_plural);
}
char *dngettext(const char *domain, const char *msgid, const char *msgid_plural, unsigned long n)
{
  (void)domain;
  return ngettext(msgid, msgid_plural, n);
}
char *dcngettext(const char *domain, const char *msgid, const char *msgid_plural,
                 unsigned long n, int category)
{
  (void)domain; (void)category;
  return ngettext(msgid, msgid_plural, n);
}
/* textdomain(NULL) asks; a name sets it. "" resets to "messages", as in glibc. */
char *textdomain(const char *domain)
{
  if (domain && !*domain) domain = "messages";
  return crtl_intl_keep(crtl_intl_domain, sizeof crtl_intl_domain, domain);
}
char *bindtextdomain(const char *domain, const char *dirname)
{
  (void)domain;
  return crtl_intl_keep(crtl_intl_dir, sizeof crtl_intl_dir, dirname);
}
char *bind_textdomain_codeset(const char *domain, const char *codeset)
{
  (void)domain;
  if (!codeset && !crtl_intl_codeset[0]) return 0;
  return crtl_intl_keep(crtl_intl_codeset, sizeof crtl_intl_codeset, codeset);
}
