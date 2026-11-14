/* SPDX-License-Identifier: Zlib */
/* C runtime: the utmpx reader (see <utmpx.h>). */
#include <utmpx.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

static int crtl_utx_fd = -1;
static char crtl_utx_path[256] = _PATH_UTMP;
static struct utmpx crtl_utx_rec;

void setutxent(void)
{
  if (crtl_utx_fd >= 0) { lseek(crtl_utx_fd, 0, SEEK_SET); return; }
  crtl_utx_fd = open(crtl_utx_path, O_RDONLY | O_CLOEXEC);
}

void endutxent(void)
{
  if (crtl_utx_fd >= 0) close(crtl_utx_fd);
  crtl_utx_fd = -1;
}

struct utmpx *getutxent(void)
{
  size_t got = 0;
  if (crtl_utx_fd < 0) setutxent();
  if (crtl_utx_fd < 0) return 0;
  while (got < sizeof crtl_utx_rec) {
    ssize_t r = read(crtl_utx_fd, (char *)&crtl_utx_rec + got, sizeof crtl_utx_rec - got);
    if (r <= 0) return 0;          /* end of file, or a torn last record */
    got += (size_t)r;
  }
  return &crtl_utx_rec;
}

struct utmpx *getutxid(const struct utmpx *ut)
{
  struct utmpx *u;
  while ((u = getutxent()) != 0) {
    if (ut->ut_type == RUN_LVL || ut->ut_type == BOOT_TIME ||
        ut->ut_type == NEW_TIME || ut->ut_type == OLD_TIME) {
      if (u->ut_type == ut->ut_type) return u;
    } else if ((u->ut_type == INIT_PROCESS || u->ut_type == LOGIN_PROCESS ||
                u->ut_type == USER_PROCESS || u->ut_type == DEAD_PROCESS) &&
               !strncmp(u->ut_id, ut->ut_id, sizeof u->ut_id))
      return u;
  }
  return 0;
}

struct utmpx *getutxline(const struct utmpx *ut)
{
  struct utmpx *u;
  while ((u = getutxent()) != 0)
    if ((u->ut_type == LOGIN_PROCESS || u->ut_type == USER_PROCESS) &&
        !strncmp(u->ut_line, ut->ut_line, sizeof u->ut_line))
      return u;
  return 0;
}

struct utmpx *pututxline(const struct utmpx *ut)
{
  (void)ut;
  errno = ENOSYS;
  return 0;
}

int utmpxname(const char *file)
{
  size_t n = strlen(file);
  if (n >= sizeof crtl_utx_path) { errno = ENAMETOOLONG; return -1; }
  endutxent();
  memcpy(crtl_utx_path, file, n + 1);
  return 0;
}
