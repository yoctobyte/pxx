/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: openlog/syslog/vsyslog/closelog/setlogmask.
 *
 * The message goes to an AF_UNIX DATAGRAM socket at /dev/log. Datagram, not
 * stream: syslogd binds SOCK_DGRAM and each call is one record, so a stream
 * socket would connect and then have its writes silently reframed by whatever
 * read them. If /dev/log does not exist -- which is the normal state on a box
 * with no syslogd, and is not an error -- the message is dropped unless
 * LOG_CONS or LOG_PERROR asked for a fallback. THAT SILENCE IS THE SPEC: a
 * program logs and continues, and syslog(3) has no way to report failure.
 *
 * THE WIRE FORMAT IS NOT OURS. "<PRI>Mmm dd hh:mm:ss ident[pid]: text" is
 * RFC 3164's, and the receiving daemon is a different program -- busybox's own
 * syslogd parses exactly this. The timestamp has a SPACE-PADDED day (`Jan  1',
 * two spaces) and no year; strftime's %e does that, and %d would emit `01',
 * which some parsers reject.
 *
 * A priority carrying no facility gets the one openlog was given, which is how
 * a caller passing a bare LOG_ERR ends up under LOG_USER rather than under
 * LOG_KERN -- facility 0 is a REAL facility, so the test has to be on the
 * facility bits and not on the whole value being small.
 *
 * Found attempting busybox rung 2: init/init.c, miscutils/crond.c,
 * sysklogd/logger.c, libbb/verror_msg.c.
 */
#include <syslog.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <fcntl.h>
#include <errno.h>

static int   log_fd = -1;
static int   log_opt;
static int   log_facility = LOG_USER;
static int   log_mask = 0xff;       /* LOG_UPTO(LOG_DEBUG): everything, as glibc starts */
static char  log_ident[64];
static int   log_have_ident;

static void log_open_socket(void) {
  struct sockaddr_un sun;
  int fd;
  if (log_fd >= 0) return;
  fd = socket(AF_UNIX, SOCK_DGRAM, 0);
  if (fd < 0) return;
  memset(&sun, 0, sizeof sun);
  sun.sun_family = AF_UNIX;
  strncpy(sun.sun_path, _PATH_LOG, sizeof sun.sun_path - 1);
  if (connect(fd, (struct sockaddr *)&sun, (socklen_t)sizeof sun) < 0) {
    close(fd);
    return;                          /* no daemon: not an error, see above */
  }
  log_fd = fd;
}

void openlog(const char *ident, int option, int facility) {
  log_opt = option;
  if (facility != 0) log_facility = facility;
  if (ident) {
    strncpy(log_ident, ident, sizeof log_ident - 1);
    log_ident[sizeof log_ident - 1] = '\0';
    log_have_ident = 1;
  } else {
    log_have_ident = 0;
  }
  if (option & LOG_NDELAY) log_open_socket();
}

void closelog(void) {
  if (log_fd >= 0) close(log_fd);
  log_fd = -1;
  log_opt = 0;
  log_facility = LOG_USER;
  log_have_ident = 0;
  log_ident[0] = '\0';
}

int setlogmask(int mask) {
  int old = log_mask;
  /* A mask of 0 QUERIES rather than silencing -- setlogmask(0) is the idiom
     for reading the current mask, and glibc leaves it unchanged. The initial
     value is 0xff, not 0, so the query has something to return and a caller
     that saves-and-restores gets back what it had. */
  if (mask != 0) log_mask = mask;
  return old;
}

void vsyslog(int priority, const char *format, va_list ap) {
  char body[1024];
  char msg[1200];
  char stamp[32];
  time_t now;
  struct tm tmv;
  int n, pri;

  /* The mask filters on the SEVERITY only -- the facility bits play no part. */
  if ((LOG_MASK(LOG_PRI(priority)) & log_mask) == 0) return;

  pri = priority;
  if ((pri & LOG_FACMASK) == 0) pri |= log_facility;

  vsnprintf(body, sizeof body, format, ap);

  now = time(0);
  stamp[0] = '\0';
  if (localtime_r(&now, &tmv))
    strftime(stamp, sizeof stamp, "%b %e %H:%M:%S", &tmv);

  if (log_opt & LOG_PID)
    n = snprintf(msg, sizeof msg, "<%d>%s %s[%d]: %s", pri, stamp,
                 log_have_ident ? log_ident : "", (int)getpid(), body);
  else
    n = snprintf(msg, sizeof msg, "<%d>%s %s%s%s", pri, stamp,
                 log_have_ident ? log_ident : "",
                 log_have_ident ? ": " : "", body);
  if (n < 0) return;
  if (n > (int)sizeof msg - 1) n = (int)sizeof msg - 1;

  log_open_socket();
  if (log_fd >= 0) {
    if (send(log_fd, msg, (size_t)n, 0) >= 0) {
      if (log_opt & LOG_PERROR) { fputs(body, stderr); fputc('\n', stderr); }
      return;
    }
    /* The daemon went away between connect and send; drop the fd so the next
       call reconnects rather than writing into a dead socket forever. */
    close(log_fd);
    log_fd = -1;
  }

  if (log_opt & LOG_PERROR) { fputs(body, stderr); fputc('\n', stderr); }
  if (log_opt & LOG_CONS) {
    int cfd = open("/dev/console", O_WRONLY | O_NOCTTY);
    if (cfd >= 0) {
      write(cfd, msg, (size_t)n);
      write(cfd, "\r\n", 2);
      close(cfd);
    }
  }
}

void syslog(int priority, const char *format, ...) {
  va_list ap;
  va_start(ap, format);
  vsyslog(priority, format, ap);
  va_end(ap);
}
