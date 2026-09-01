/* The crtl surface a 79-applet busybox userland needed, all of it measured
   against glibc rather than reasoned about. Every row here failed to COMPILE
   before the functions existed, so the file's existence is half the assertion;
   the values are the other half, and each was diffed against a gcc build of
   this same source.

   WHAT EACH ROW IS ACTUALLY FOR -- these are the ones with a wrong answer
   available, which is why they are the rows:

     2  hasmntopt must match a WHOLE comma-separated element. The substring
        reading says `ro' is present in `errors=remount-ro' and `dev' in
        `nodev', and it answers yes to a question nobody asked.
     3  the octal escapes in a mount table are DECODED -- a mount point with a
        space is written `\040' and a reader that skips this returns a path
        that does not exist.
     4  freq and passno are OPTIONAL; /proc/mounts writes them and a hand-made
        /etc/mtab line often does not.
     5  getline KEEPS the delimiter and returns a byte count, not strlen, and
        the last line of a file with no trailing newline is still a line.
     7  getgroups(0, NULL) asks for the COUNT without touching the list -- the
        call every caller makes first, to size its array.
     8  RAND_MAX is 31 bits and the GENERATOR agrees. Raising the macro over a
        15-bit generator leaves every high bit zero, which passes an in-range
        test and fails the row below it.

   feature-c-crtl-gaps-for-a-79-applet-busybox-userland */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <grp.h>
#include <mntent.h>
#include <sys/wait.h>

static const char *MTAB =
  "# a comment\n"
  "/dev/sda1 /mnt/my\\040disk ext4 rw,errors=remount-ro 0 2\n"
  "\n"
  "/dev/sdb1   /mnt/plain    xfs      ro,noauto\n";

int main(void) {
  char path[] = "/tmp/c_crtl_bb_mtabXXXXXX";
  char lpath[] = "/tmp/c_crtl_bb_lineXXXXXX";
  int fd;
  FILE *f;
  struct mntent *m;
  struct group *g;
  char *line = 0;
  size_t n = 0;
  ssize_t r;
  gid_t gs[64];
  int cnt, i, in_range = 1, saw_high = 0;
  long v;

  fd = mkstemp(path);
  write(fd, MTAB, strlen(MTAB));
  close(fd);

  /* A ROUND TRIP, not a name. Asserting that gid 0 is called "root" would make
     this row a claim about the BOX rather than about the lookup, and it would
     fail on a system that names it `wheel'. What must hold everywhere is that
     the two lookups agree. It still needs a readable /etc/group, and prints 0
     rather than pretending otherwise if there is none. */
  g = getgrgid(0);
  { struct group *back = g ? getgrnam(g->gr_name) : 0;
    printf("1 %d\n", (g && back && back->gr_gid == 0) ? 1 : 0); }

  f = setmntent(path, "r");
  m = getmntent(f);
  printf("2 ro=%d rw=%d\n", hasmntopt(m, "ro") ? 1 : 0, hasmntopt(m, "rw") ? 1 : 0);
  printf("3 [%s]\n", m->mnt_dir);
  printf("4 %d %d\n", m->mnt_freq, m->mnt_passno);
  m = getmntent(f);
  printf("5 [%s] %d %d\n", m->mnt_dir, m->mnt_freq, m->mnt_passno);
  endmntent(f);

  /* getline: a file whose last line has no newline. */
  fd = mkstemp(lpath);
  write(fd, "one\ntwo", 7);
  close(fd);
  f = fopen(lpath, "r");
  i = 0;
  while ((r = getline(&line, &n, f)) != -1) printf("6.%d %zd\n", i++, r);
  free(line);
  /* SEQUENCED, and it has to be: `printf("%lld %d", ftello(f), fgetc(f))' has
     no defined argument evaluation order, so the position reported would depend
     on whether the getc ran first. Both compilers happened to agree, which is
     exactly how an unspecified-behaviour row passes and means nothing. */
  fseeko(f, 4, SEEK_SET);
  { long long pos = (long long)ftello(f);
    int ch = fgetc(f);
    printf("7 %lld %d\n", pos, ch); }
  fclose(f);

  cnt = getgroups(0, 0);
  printf("8 %d\n", getgroups(64, gs) == cnt);

  srand(1);
  for (i = 0; i < 20000; i++) {
    v = rand();
    if (v < 0 || v > RAND_MAX) in_range = 0;
    if (v > 0x3fffffffL) saw_high = 1;
  }
  printf("9 %d %d %d\n", RAND_MAX == 0x7fffffff, in_range, saw_high);

  f = popen("echo piped", "r");
  { char buf[64]; int st;
    buf[0] = 0;
    if (f && fgets(buf, sizeof buf, f)) { }
    st = WEXITSTATUS(pclose(f));
    printf("10 [%s] %d\n", buf, st); }
  { int avail = system(NULL);
    int st = WEXITSTATUS(system("exit 5"));
    printf("11 %d %d\n", avail, st); }

  remove(path);
  remove(lpath);
  return 0;
}
