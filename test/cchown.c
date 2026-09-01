/* chown/lchown: the path-based pair. crtl had only fchown (by descriptor), so
   busybox's libbb/copy_file.c -- which preserves ownership when copying a tree
   -- did not compile at all: `call to undeclared function: lchown`.
   feature-c-corpus-busybox-multi-applet

   UNPRIVILEGED BY CONSTRUCTION. Both calls use (uid_t)-1/(gid_t)-1, POSIX's
   "leave this field unchanged", which succeeds for the file's owner without
   any privilege. So the test exercises the syscall, the path argument and the
   AT_SYMLINK_NOFOLLOW flag without needing root, and its result does not
   depend on who runs it.

   THE DANGLING-LINK ROW IS THE ONE THAT SEPARATES THE TWO CALLS. A symlink
   pointing at a name that does not exist: chown FOLLOWS it and must fail with
   ENOENT, lchown changes the LINK ITSELF and must succeed. An lchown that
   quietly forgot AT_SYMLINK_NOFOLLOW passes every other row here.

   errno is read in its own statement, never as a second printf argument beside
   the call that sets it: the order of evaluation of function arguments is
   unspecified, and gcc and pxx genuinely choose differently. */
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

static void show(const char *tag, int rc)
{
  int e = errno;
  printf("%s %d %s\n", tag, rc < 0 ? -1 : 0, rc < 0 ? strerror(e) : "-");
}

int main(void)
{
  int rc;

  remove("cchown_file"); remove("cchown_link"); remove("cchown_dangling");
  { FILE *f = fopen("cchown_file", "w"); if (!f) { puts("cannot create"); return 1; } fputs("x", f); fclose(f); }
  if (symlink("cchown_file", "cchown_link") != 0)      { puts("cannot symlink"); return 1; }
  if (symlink("cchown_nowhere", "cchown_dangling") != 0) { puts("cannot symlink"); return 1; }

  errno = 0; rc = chown("cchown_file", (uid_t)-1, (gid_t)-1);      show("chown-file", rc);
  errno = 0; rc = lchown("cchown_file", (uid_t)-1, (gid_t)-1);     show("lchown-file", rc);
  errno = 0; rc = chown("cchown_link", (uid_t)-1, (gid_t)-1);      show("chown-link", rc);
  errno = 0; rc = lchown("cchown_link", (uid_t)-1, (gid_t)-1);     show("lchown-link", rc);
  /* the discriminating pair */
  errno = 0; rc = chown("cchown_dangling", (uid_t)-1, (gid_t)-1);  show("chown-dangling", rc);
  errno = 0; rc = lchown("cchown_dangling", (uid_t)-1, (gid_t)-1); show("lchown-dangling", rc);
  errno = 0; rc = chown("cchown_missing", (uid_t)-1, (gid_t)-1);   show("chown-missing", rc);
  errno = 0; rc = lchown("cchown_missing", (uid_t)-1, (gid_t)-1);  show("lchown-missing", rc);

  remove("cchown_file"); remove("cchown_link"); remove("cchown_dangling");
  return 0;
}
