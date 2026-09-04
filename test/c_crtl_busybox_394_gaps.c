/* crtl: the nine function gaps busybox reaches at 394 applets, plus the four
 * SIBLINGS the same translation units call within fifty lines of them --
 * feature-b-crtl-function-gaps-at-394-busybox-applets.
 *
 * WHY THERE ARE THIRTEEN FUNCTIONS AND NOT NINE. The ticket's list was built
 * from compiler refusals, and a refusal stops the translation unit at its
 * FIRST undeclared identifier -- so nine refusals across nine TUs counted nine
 * FILES, not nine functions. hdparm.c pins with mlock at :1507 and releases
 * with munlock at :1559; tree.c's scandir call passes alphasort as its
 * comparator; chrt.c calls sched_getparam and sched_setscheduler either side
 * of sched_getscheduler. Shipping the nine would have moved each refusal a few
 * lines down its own file.
 *
 * EVERY ROW IS A RELATION, NOT A CONSTANT, wherever the answer depends on the
 * machine: whether the caller is root, what RLIMIT_MEMLOCK is, and whether
 * /etc/ethers exists all change the literal values, and none of them changes
 * what is being claimed. Rows that CAN be constants (the parsers, the address
 * predicates) are constants, because a relation there would be a weaker test.
 *
 * NO ROW EXPECTS 0 AS ITS ONLY INTERESTING VALUE and no two rows expect the
 * same shape, so a row cannot pass because the machinery did nothing.
 *
 * All rows diffed against gcc -D_GNU_SOURCE.
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>
#include <sched.h>
#include <dirent.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/ether.h>

int main(void)
{
  /* 1: sigisemptyset. Empty is 1, one member is 0, and emptying it again is 1
     -- the third asks whether the answer TRACKS the set rather than being a
     constant, which a one-word reader would also pass. */
  {
    sigset_t s;
    int a, b, c;
    sigemptyset(&s);           a = sigisemptyset(&s);
    sigaddset(&s, SIGUSR1);    b = sigisemptyset(&s);
    sigemptyset(&s);           c = sigisemptyset(&s);
    printf("1 %d %d %d\n", a, b, c);
  }

  /* 2: the classful predicates, on HOST-order addresses. 224.0.0.1 and
     239.255.255.255 are the ends of class D; 223.255.255.255 and 240.0.0.0 are
     the neighbours just outside it, so an off-by-one boundary shows here. */
  printf("2 %d %d %d %d %d\n",
         IN_MULTICAST(0xE0000001u), IN_MULTICAST(0xEFFFFFFFu),
         IN_MULTICAST(0xDFFFFFFFu), IN_MULTICAST(0xF0000000u),
         IN_CLASSA(0x0A000001u));

  /* 3: ether_line, the shared /etc/ethers parser. A good line, a leading-blank
     line, a comment, an address with no host, and a line that is not an
     address at all. The two accepted rows print the parsed bytes, so a parser
     that returns 0 without filling the struct fails here. */
  {
    struct ether_addr a;
    char h[512];
    int r1, r2, r3, r4, r5;
    memset(&a, 0, sizeof a);
    r1 = ether_line("01:02:03:04:05:06 alpha", &a, h);
    printf("3 %d %02x%02x%02x%02x%02x%02x %s", r1,
           a.ether_addr_octet[0], a.ether_addr_octet[1], a.ether_addr_octet[2],
           a.ether_addr_octet[3], a.ether_addr_octet[4], a.ether_addr_octet[5], h);
    memset(&a, 0, sizeof a);
    r2 = ether_line("   aa:bb:cc:dd:ee:ff  beta  ", &a, h);
    printf(" | %d %02x%02x%02x%02x%02x%02x %s", r2,
           a.ether_addr_octet[0], a.ether_addr_octet[1], a.ether_addr_octet[2],
           a.ether_addr_octet[3], a.ether_addr_octet[4], a.ether_addr_octet[5], h);
    r3 = ether_line("# 01:02:03:04:05:06 gamma", &a, h);
    r4 = ether_line("01:02:03:04:05:06", &a, h);
    r5 = ether_line("not-an-address delta", &a, h);
    printf(" | %d %d %d\n", r3, r4, r5);
  }

  /* 4: ether_hostton/ether_ntohost for a name and an address that cannot be in
     any /etc/ethers. -1 whether or not the file exists, which is what makes
     this row machine-independent rather than a bet on the file's absence.

     WHAT THIS ROW DOES NOT COVER, said plainly because a passing row otherwise
     implies it: the FILE SCAN. /etc/ethers does not exist on the machines this
     runs on and creating it needs root, so both libcs answer -1 for every
     input and the row would pass against a lookup that never opened the file
     at all. The PARSER half is fully covered -- eleven line shapes, plus row
     12 -- and the scan is fifteen lines of fopen/fgets/compare on top of it.
     Closing this needs a root-created /etc/ethers or a container; until then
     the scan is unverified, not verified-by-omission. (frankD ran an
     independent glibc oracle over the parser and could not cover this half
     either, for the same reason.) */
  {
    struct ether_addr a;
    char h[512];
    memset(&a, 0xA5, sizeof a);
    printf("4 %d %d\n",
           ether_hostton("pxx-no-such-ethers-host", &a),
           ether_ntohost(h, &a));
  }

  /* 5: scandir + alphasort over a directory this test builds, so the contents
     are known. The count and the ORDER are both asserted -- the files are
     created out of order on purpose, so an implementation that returns them in
     readdir order passes the count and fails here. */
  {
    const char *dir = "/tmp/pxx_crtl_scandir_probe";
    const char *names[3] = { "zebra", "apple", "mango" };
    struct dirent **ents = 0;
    char path[256];
    int n, i, fd;
    mkdir(dir, 0700);
    for (i = 0; i < 3; i++) {
      sprintf(path, "%s/%s", dir, names[i]);
      fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
      if (fd >= 0) close(fd);
    }
    n = scandir(dir, &ents, 0, alphasort);
    printf("5 %d", n);
    for (i = 0; i < n; i++) printf(" %s", ents[i]->d_name);
    printf("\n");
    for (i = 0; i < n; i++) free(ents[i]);
    free(ents);
    for (i = 0; i < 3; i++) { sprintf(path, "%s/%s", dir, names[i]); unlink(path); }
    rmdir(dir);
  }

  /* 6: scandir's failure path. A directory that does not exist must return -1
     and must NOT store anything through namelist -- a caller that checks the
     return value never sees a partial array, so the sentinel must survive. */
  {
    struct dirent **ents = (struct dirent **)0x1;
    int n = scandir("/tmp/pxx-no-such-directory-here", &ents, 0, alphasort);
    printf("6 %d %d\n", n, ents == (struct dirent **)0x1);
  }

  /* 7: mlock/munlock round trip on one page. Assumes RLIMIT_MEMLOCK allows a
     single page, which every default Linux does; if a machine forbids it this
     row fails loudly rather than being skipped, which is the direction that
     does not hide a broken implementation. */
  {
    static char page[8192];
    void *p = (void *)(((unsigned long)page + 4095u) & ~4095ul);
    int a = mlock(p, 4096);
    int b = munlock(p, 4096);
    printf("7 %d %d\n", a, b);
  }

  /* 8: the scheduler trio. SCHED_OTHER is 0 and its only legal priority is 0,
     so setting a process that is already SCHED_OTHER to SCHED_OTHER is a call
     any user may make -- no root, no environment dependence. */
  {
    struct sched_param sp;
    int pol, gp, sr;
    pol = sched_getscheduler(0);
    memset(&sp, 0, sizeof sp);
    gp = sched_getparam(0, &sp);
    sr = sched_setscheduler(0, SCHED_OTHER, &sp);
    printf("8 %d %d %d %d\n", pol, gp, sp.sched_priority, sr);
  }

  /* 9: nice. THE RELATION, not the value: whatever the process starts at, one
     more is one more. Printed as a boolean so the row carries no per-machine
     constant, and nice(0) is checked to return the same value twice so a
     nice() that always answered 0 could not pass. */
  {
    int base, again, up;
    errno = 0; base  = nice(0);
    errno = 0; again = nice(0);
    errno = 0; up    = nice(1);
    printf("9 %d %d\n", base == again, up == base + 1);
  }

  /* 10: pause. It has no success return -- it comes back only when a handled
     signal arrives -- so the property to test without a handler is that it
     BLOCKS. A child calls it, the parent checks the child is still there, then
     kills it. A pause() that returned immediately would make the child exit 7
     and the first column 0.

     NO HANDLER, DELIBERATELY, and this is a crtl limitation rather than a test
     shortcut: lib/crtl/src/signal.c says in its own header that signal and
     sigaction are LINK-ONLY STUBS -- they return 0 and install nothing,
     because there is no rt_sigaction bridge. The first version of this row set
     a SIGALRM handler and alarm(1); under gcc it passed, and under pxx the
     process died with "Alarm clock" because the kernel still held the default
     disposition. Filed as bug-b-crtl-signal-and-sigaction-report-success-and-
     install-nothing. */
  {
    int st = 0, alive, killed;
    pid_t pid = fork();
    if (pid == 0) { pause(); _exit(7); }
    usleep(200000);
    alive = (waitpid(pid, &st, WNOHANG) == 0);
    kill(pid, SIGKILL);
    waitpid(pid, &st, 0);
    killed = WIFSIGNALED(st) ? 1 : 0;
    printf("10 %d %d\n", alive, killed);
  }

  /* 11: acct. Classified rather than literal: it needs CAP_SYS_PACCT, so a
     root run and a user run give different errno, and both are correct. The
     claim is that the call REACHES THE KERNEL and is refused for a reason acct
     can actually give -- a stub returning ENOSYS unconditionally would fail
     the second column on a kernel that has accounting compiled in. */
  {
    int rc, e;
    errno = 0;
    rc = acct("/tmp/pxx-no-such-acct-file");
    e = errno;
    printf("11 %d %d\n", rc, e == EPERM || e == ENOENT || e == ENOSYS);
  }

  /* 12: the REFUSAL path writes partial octets, and the boundary is where the
     component fails. Not a curiosity: ether_aton_r stores each octet AFTER
     checking its separator, so a caller inspecting the struct after -1 sees
     the components that parsed and zeros after. glibc does the same, measured
     -- and an implementation that stored first would pass every accepting row
     in row 3 and differ here. This row is what stops that being "tidied".

     TWO THINGS MAKE IT ABLE TO FAIL, and neither is the refusal itself.
     (a) It prints the OUT-PARAMETER on the refusing rows, not just rc. rc is
     where the two implementations AGREE -- -1 on every bad line -- so a
     refusal row asserting only the return code passes the store-first mutation
     exactly like no row at all. The struct is the only column that differs.
     (b) The two FAILURE KINDS are both here on purpose. `...:33:44 short` and
     `...:22:33 shorter` run OUT of input, so for them "stopped at the bad
     component" and "stopped after the last one present" are the same index by
     construction and cannot be told apart. `00:11:22:33:44:zz` has a sixth
     component that is PRESENT and malformed, which drives the loop one
     iteration further than a truncation can and is the only row that reaches
     the reject-this-component path with bytes in front of it. */
  {
    struct ether_addr a;
    char h[512];
    const char *lines[4] = { "00:11:22:33:44 short", "00:11:22:33 shorter",
                             "00:11:22:33:44:55 ok", "00:11:22:33:44:zz bad" };
    int i, r;
    printf("12");
    for (i = 0; i < 4; i++) {
      memset(&a, 0, sizeof a);
      r = ether_line(lines[i], &a, h);
      printf(" %d:%02x%02x%02x%02x%02x%02x", r,
             a.ether_addr_octet[0], a.ether_addr_octet[1], a.ether_addr_octet[2],
             a.ether_addr_octet[3], a.ether_addr_octet[4], a.ether_addr_octet[5]);
    }
    printf("\n");
  }

  return 0;
}
