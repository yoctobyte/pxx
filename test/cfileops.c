/* chdir / symlink / link (feature-crtl-process-file-ops-batch).
 *
 * These needed new PAL surface in both backends. symlink and link reach the
 * kernel through symlinkat/linkat with AT_FDCWD, not the legacy syscalls:
 * aarch64 and riscv do not HAVE symlink/link, so the *at form is the only
 * spelling that exists everywhere — the same reason openat/unlinkat/renameat
 * are used elsewhere in the backend.
 *
 * Asserted behaviourally: chdir must make a RELATIVE path resolve against the
 * new directory (not merely return 0), lstat must see a link where stat
 * follows it, and the hard link must expose the same content. Failure cases
 * must fail. Whole output diffed against the same file built by gcc.
 *
 * The cross-target run is the real verification of the per-arch syscall
 * numbers: x86-64, i386 and the asm-generic pair came from kernel headers on
 * the build box, but arm32's were derived from the surrounding table order,
 * so qemu-arm agreeing with gcc is what actually confirms them.
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
int main(void) {
  char cwd[256]; struct stat st; FILE *f; int rc; long sz;
  const char *dir = "/tmp/pxx_fops_probe";
  const char *tgt = "/tmp/pxx_fops_probe/orig.txt";
  const char *sym = "/tmp/pxx_fops_probe/sym.txt";
  const char *hrd = "/tmp/pxx_fops_probe/hard.txt";
  mkdir(dir, 0755);
  f = fopen(tgt, "wb"); fwrite("payload", 1, 7, f); fclose(f);
  /* chdir + getcwd round trip */
  rc = chdir(dir);        printf("chdir=%d\n", rc == 0);
  getcwd(cwd, sizeof(cwd)); printf("cwd_ok=%d\n", strcmp(cwd, dir) == 0);
  /* a relative path must now resolve against the new cwd */
  rc = stat("orig.txt", &st); sz = (long)st.st_size;
  printf("relative_resolves=%d size=%ld\n", rc == 0, rc == 0 ? sz : -1L);
  rc = chdir("/tmp");     printf("chdir_back=%d\n", rc == 0);
  getcwd(cwd, sizeof(cwd)); printf("cwd_back=%d\n", strcmp(cwd, "/tmp") == 0);
  /* symlink: lstat sees a link, stat follows it */
  rc = symlink(tgt, sym); printf("symlink=%d\n", rc == 0);
  rc = lstat(sym, &st);   printf("lstat_islink=%d\n", rc == 0 && S_ISLNK(st.st_mode) != 0);
  rc = stat(sym, &st); sz = (long)st.st_size;
  printf("stat_follows=%d size=%ld\n", rc == 0, rc == 0 ? sz : -1L);
  /* hard link: same inode, link count 2 */
  rc = link(tgt, hrd);    printf("link=%d\n", rc == 0);
  rc = stat(hrd, &st); sz = (long)st.st_size;
  printf("hard_size=%ld\n", rc == 0 ? sz : -1L);
  /* the hard link must expose the SAME content, which is what makes it a link
     rather than a copy. st_nlink is deliberately not asserted: crtl hardcodes
     it to 1 (bug-b-crtl-stat-nlink-hardcoded), a separate pre-existing stub. */
  { FILE *h = fopen(hrd, "rb"); char hb[16]; long hn = 0;
    if (h) { hn = (long)fread(hb, 1, 7, h); fclose(h); }
    hb[hn > 0 ? hn : 0] = 0;
    printf("hard_content=[%s]\n", hb); }
  /* failures report an error rather than succeeding quietly */
  printf("chdir_missing=%d\n", chdir("/tmp/pxx_no_such_dir_zz") != 0);
  printf("symlink_exists=%d\n", symlink(tgt, sym) != 0);
  remove(sym); remove(hrd); remove(tgt); rmdir(dir);
  return 0;
}
