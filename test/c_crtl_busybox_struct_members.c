/* The struct members busybox reads that crtl lacked, each found when the
   member check (2026-09-24) started refusing what pxx used to read at offset 0:
   st_atim/st_mtim/st_ctim (coreutils/stat.c), ipc_perm.key and msg_cbytes
   (util-linux/ipcs.c), struct in_pktinfo (libbb/udp_io.c). Values are set and
   read back; the stat times come from utimensat, so nanoseconds are fixed. */
#include <stdio.h>
#include <stddef.h>
#include <fcntl.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/ipc.h>
#include <sys/msg.h>
#include <netinet/in.h>
#include <stdlib.h>

int main(void) {
  /* the run's own scratch first (TESTMGR_TMP survives testmgr's environment
     allowlist; TESTTMP is what `make test` sets), so parallel runs differ */
  const char *dir = getenv("TESTMGR_TMP");
  char path[512];
  struct timespec ts[2];
  struct stat st;
  struct ipc_perm perm;
  struct msqid_ds q;
  struct in_pktinfo pk;
  int fd;
  if (!dir || !*dir) dir = getenv("TESTTMP");
  if (!dir || !*dir) dir = "/tmp";
  snprintf(path, sizeof path, "%s/pxx_c_crtl_busybox_struct_members", dir);
  fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0644);
  if (fd < 0) { puts("open failed"); return 1; }
  close(fd);
  ts[0].tv_sec = 1000000000; ts[0].tv_nsec = 123456789;   /* atime */
  ts[1].tv_sec = 1700000000; ts[1].tv_nsec = 987654321;   /* mtime */
  if (utimensat(AT_FDCWD, path, ts, 0) != 0) { puts("utimensat failed"); return 1; }
  if (stat(path, &st) != 0) { puts("stat failed"); return 1; }
  printf("atim %ld.%09ld mtim %ld.%09ld\n", (long)st.st_atim.tv_sec, (long)st.st_atim.tv_nsec,
         (long)st.st_mtim.tv_sec, (long)st.st_mtim.tv_nsec);
  printf("st_atime=st_atim.tv_sec %d st_mtime=st_mtim.tv_sec %d ctim.nsec<1e9 %d\n",
         st.st_atime == st.st_atim.tv_sec, st.st_mtime == st.st_mtim.tv_sec,
         st.st_ctim.tv_nsec >= 0 && st.st_ctim.tv_nsec < 1000000000);
  unlink(path);

  perm.__key = 0x5eed; perm.seq = 3;
  printf("key %x %x seq %d %d\n", perm.key, perm.__key, perm.seq, perm.__seq);
  q.__msg_cbytes = 4242;
  printf("msg_cbytes %lu\n", (unsigned long)q.msg_cbytes);
  pk.ipi_ifindex = 2;
  pk.ipi_spec_dst.s_addr = 0x0100007f;
  printf("in_pktinfo %d %d %d %x\n", (int)sizeof pk, (int)offsetof(struct in_pktinfo, ipi_spec_dst),
         (int)offsetof(struct in_pktinfo, ipi_addr), (unsigned)pk.ipi_spec_dst.s_addr);
  printf("ipc_perm %d %d\n", (int)sizeof perm, (int)offsetof(struct ipc_perm, __seq));
  return 0;
}
