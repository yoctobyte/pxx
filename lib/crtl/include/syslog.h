/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <syslog.h>.
 *
 * THE PRIORITY IS TWO FIELDS IN ONE INT and that is the whole trap: the low
 * three bits are the severity, everything above is the facility, and a caller
 * that ORs them is doing arithmetic the macros below already did. LOG_PRI and
 * LOG_FAC split them back apart; LOG_MAKEPRI puts them together. A severity
 * passed where a priority is expected simply logs under LOG_KERN, silently,
 * because facility 0 is a real facility.
 *
 * The numbering is RFC 3164's and the kernel's -- these values travel over the
 * wire to a syslog daemon that is not this program and may not be this
 * runtime, so they are not ours to choose.
 *
 * SYSLOG_NAMES: define it before including this header to get the
 * `prioritynames' and `facilitynames' tables, as BSD and glibc do. busybox's
 * sysklogd/syslogd.c and logger.c both do exactly that. The tables are
 * declared static-storage here rather than exported, which is also what those
 * headers do -- each translation unit that asks gets its own copy, and nothing
 * links against a table it did not ask for.
 *
 * Found attempting busybox rung 2: init/init.c, miscutils/crond.c,
 * sysklogd/logger.c, and every applet reached through libbb's bb_error_msg
 * with logmode & LOGMODE_SYSLOG.
 */
#ifndef _CRTL_SYSLOG_H
#define _CRTL_SYSLOG_H

#include <stdarg.h>

/* Severities, most urgent first. */
#define LOG_EMERG   0   /* system is unusable */
#define LOG_ALERT   1   /* action must be taken immediately */
#define LOG_CRIT    2   /* critical conditions */
#define LOG_ERR     3   /* error conditions */
#define LOG_WARNING 4   /* warning conditions */
#define LOG_NOTICE  5   /* normal but significant */
#define LOG_INFO    6   /* informational */
#define LOG_DEBUG   7   /* debug-level messages */

#define LOG_PRIMASK 0x07
#define LOG_PRI(p)  ((p) & LOG_PRIMASK)
#define LOG_MAKEPRI(fac, pri) ((fac) | (pri))

/* Facilities. The value is ALREADY SHIFTED (<<3) -- that is the historical
   encoding, so LOG_MAKEPRI is an OR and not a shift. */
#define LOG_KERN     (0<<3)
#define LOG_USER     (1<<3)
#define LOG_MAIL     (2<<3)
#define LOG_DAEMON   (3<<3)
#define LOG_AUTH     (4<<3)
#define LOG_SYSLOG   (5<<3)
#define LOG_LPR      (6<<3)
#define LOG_NEWS     (7<<3)
#define LOG_UUCP     (8<<3)
#define LOG_CRON     (9<<3)
#define LOG_AUTHPRIV (10<<3)
#define LOG_FTP      (11<<3)
#define LOG_LOCAL0   (16<<3)
#define LOG_LOCAL1   (17<<3)
#define LOG_LOCAL2   (18<<3)
#define LOG_LOCAL3   (19<<3)
#define LOG_LOCAL4   (20<<3)
#define LOG_LOCAL5   (21<<3)
#define LOG_LOCAL6   (22<<3)
#define LOG_LOCAL7   (23<<3)

#define LOG_NFACILITIES 24
#define LOG_FACMASK 0x03f8
#define LOG_FAC(p)  (((p) & LOG_FACMASK) >> 3)

#define LOG_MASK(pri) (1 << (pri))
#define LOG_UPTO(pri) ((1 << ((pri)+1)) - 1)

/* openlog options. */
#define LOG_PID    0x01   /* log the pid with each message */
#define LOG_CONS   0x02   /* log to the console if the log socket fails */
#define LOG_ODELAY 0x04   /* delay open until the first syslog() -- the default */
#define LOG_NDELAY 0x08   /* open the connection immediately */
#define LOG_NOWAIT 0x10   /* historical; no effect */
#define LOG_PERROR 0x20   /* also write to stderr */

#ifdef SYSLOG_NAMES
/* The name<->value tables. `c_name' is NOT const in the BSD original and
   programs assign to it, so it is a plain char* here too. Terminated by a
   NULL name -- INTERNAL_NOPRI marks the "no priority" pseudo-entry the
   original carries and busybox skips. */
# define INTERNAL_NOPRI 0x10
# define INTERNAL_MARK  (LOG_NFACILITIES<<3)
typedef struct _code { char *c_name; int c_val; } CODE;
static CODE prioritynames[] = {
  { (char *)"alert",   LOG_ALERT },
  { (char *)"crit",    LOG_CRIT },
  { (char *)"debug",   LOG_DEBUG },
  { (char *)"emerg",   LOG_EMERG },
  { (char *)"err",     LOG_ERR },
  { (char *)"error",   LOG_ERR },        /* DEPRECATED */
  { (char *)"info",    LOG_INFO },
  { (char *)"none",    INTERNAL_NOPRI }, /* INTERNAL */
  { (char *)"notice",  LOG_NOTICE },
  { (char *)"panic",   LOG_EMERG },      /* DEPRECATED */
  { (char *)"warn",    LOG_WARNING },    /* DEPRECATED */
  { (char *)"warning", LOG_WARNING },
  { (char *)0, -1 }
};
static CODE facilitynames[] = {
  { (char *)"auth",     LOG_AUTH },
  { (char *)"authpriv", LOG_AUTHPRIV },
  { (char *)"cron",     LOG_CRON },
  { (char *)"daemon",   LOG_DAEMON },
  { (char *)"ftp",      LOG_FTP },
  { (char *)"kern",     LOG_KERN },
  { (char *)"lpr",      LOG_LPR },
  { (char *)"mail",     LOG_MAIL },
  { (char *)"mark",     INTERNAL_MARK }, /* INTERNAL */
  { (char *)"news",     LOG_NEWS },
  { (char *)"security", LOG_AUTH },      /* DEPRECATED */
  { (char *)"syslog",   LOG_SYSLOG },
  { (char *)"user",     LOG_USER },
  { (char *)"uucp",     LOG_UUCP },
  { (char *)"local0",   LOG_LOCAL0 },
  { (char *)"local1",   LOG_LOCAL1 },
  { (char *)"local2",   LOG_LOCAL2 },
  { (char *)"local3",   LOG_LOCAL3 },
  { (char *)"local4",   LOG_LOCAL4 },
  { (char *)"local5",   LOG_LOCAL5 },
  { (char *)"local6",   LOG_LOCAL6 },
  { (char *)"local7",   LOG_LOCAL7 },
  { (char *)0, -1 }
};
#endif

/* The path the messages go to. Not configurable at runtime, as in glibc. */
#define _PATH_LOG "/dev/log"

void openlog(const char *ident, int option, int facility);
void syslog(int priority, const char *format, ...);
void vsyslog(int priority, const char *format, va_list ap);
void closelog(void);
/* Returns the PREVIOUS mask, and a mask of 0 QUERIES rather than silences:
   setlogmask(0) is the idiom for reading the current one, so it must leave it
   alone. The initial mask is 0xff (everything), which is what makes that
   query meaningful. */
int setlogmask(int mask);

#endif
