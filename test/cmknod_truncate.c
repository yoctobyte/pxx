/* truncate (by PATH) and mknod/mkfifo, the file-metadata calls crtl had only
   the descriptor-based half of. busybox's libbb/copy_file.c needs both when
   copying a tree: `truncate` for a sparse target, `mknod` to recreate whatever
   node type it found. Without them it does not compile.
   feature-c-corpus-busybox-multi-applet

   UNPRIVILEGED BY CONSTRUCTION. Only S_IFIFO nodes are created -- a FIFO needs
   no privilege, a character or block device does. mknod's `dev` argument is
   ignored for a FIFO, which is why passing 0 is correct here and not a
   shortcut.

   The `mkfifo == mknod|S_IFIFO` row is the one worth having: mkfifo is defined
   by POSIX as exactly that, and implementing it as a separate path is how the
   two drift.

   errno is read in its own statement, never as a second printf argument beside
   the call that sets it -- argument evaluation order is unspecified and gcc
   and pxx genuinely differ. */
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/stat.h>

static void show(const char *tag, int rc)
{
  int e = errno;
  printf("%s %d %s\n", tag, rc < 0 ? -1 : 0, rc < 0 ? strerror(e) : "-");
}

static long size_of(const char *p)
{
  struct stat st;
  if (stat(p, &st) != 0) return -1;
  return (long)st.st_size;
}

int main(void)
{
  int rc;
  struct stat st;

  remove("cmt_file"); remove("cmt_fifo1"); remove("cmt_fifo2");
  { FILE *f = fopen("cmt_file", "w"); if (!f) { puts("cannot create"); return 1; }
    fputs("0123456789", f); fclose(f); }

  printf("size-initial %ld\n", size_of("cmt_file"));
  errno = 0; rc = truncate("cmt_file", 4);  show("truncate-shrink", rc);
  printf("size-after-shrink %ld\n", size_of("cmt_file"));
  errno = 0; rc = truncate("cmt_file", 20); show("truncate-grow", rc);
  printf("size-after-grow %ld\n", size_of("cmt_file"));
  errno = 0; rc = truncate("cmt_missing", 1); show("truncate-missing", rc);

  errno = 0; rc = mknod("cmt_fifo1", S_IFIFO | 0600, 0); show("mknod-fifo", rc);
  printf("is-fifo-1 %d\n", stat("cmt_fifo1", &st) == 0 && S_ISFIFO(st.st_mode));
  errno = 0; rc = mkfifo("cmt_fifo2", 0600); show("mkfifo", rc);
  printf("is-fifo-2 %d\n", stat("cmt_fifo2", &st) == 0 && S_ISFIFO(st.st_mode));
  errno = 0; rc = mknod("cmt_fifo1", S_IFIFO | 0600, 0); show("mknod-exists", rc);

  remove("cmt_file"); remove("cmt_fifo1"); remove("cmt_fifo2");
  return 0;
}
