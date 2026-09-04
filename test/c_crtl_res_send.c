/* SPDX-License-Identifier: Zlib */
/* res_query() against a DNS server this test starts itself on 127.0.0.1.
 *
 * A LOCAL SERVER RATHER THAN A REAL LOOKUP, for the same reason
 * c_crtl_resolv.c uses a canned packet: a test that queried the internet
 * would be measuring the network. It would pass on a box with DNS, fail on
 * one without, and neither result would say anything about the resolver. The
 * server here answers in a fixed way, so both compilers see the same bytes.
 *
 * TWO OF THE FOUR ROWS ARE SPOOFING ROWS AND THEY ARE THE POINT. res_nsend()
 * accepts a datagram only if the id matches the query and the response bit is
 * set. Neither check can fail a normal lookup -- a well-behaved server always
 * satisfies both -- so a resolver with both deleted passes every ordinary
 * test ever written for it. The `spoof' and `notresp' rows make the server
 * send a WRONG packet first and the right one second: a resolver that checks
 * gets the right answer, and one that does not gets the decoy, which here
 * carries a visibly different address.
 *
 * THE DECOY'S ADDRESS IS 6.6.6.6 AND THE REAL ONE IS 10.1.2.3 ON PURPOSE.
 * If the decoy carried the same record, accepting it would produce the right
 * answer and the row could not fail -- the exact "expected value collides
 * with the failure value" trap. They have to differ for the row to mean
 * anything.
 *
 * THE `notresp' ROW IS A DELIBERATE DIVERGENCE FROM glibc AND THE MAKEFILE
 * EXCLUDES IT FROM THE DIFF. glibc accepts the QR-clear decoy on the matching
 * id alone and prints 6.6.6.6; crtl skips it and prints 10.1.2.3. RFC 1035
 * 4.1.1 makes QR the bit that says which of the two a message is, so a
 * datagram with it clear is not an answer to anything. See
 * known-incompat/incompat-b-crtls-dns-parser-refuses-two-malformed-packets-glibc-accepts.
 * The `spoof' row, by contrast, is one both agree on -- it is here because a
 * resolver could pass `notresp' by luck and still have no id check at all.
 *
 * NXDOMAIN IS A ROW BECAUSE IT IS AN ANSWER, NOT AN ERROR. res_query()
 * returns -1 for it, the same as for a timeout, and only h_errno separates
 * them: HOST_NOT_FOUND means the name does not exist and TRY_AGAIN means
 * nobody answered. A caller that reads only the return value retries a name
 * that will never resolve. */

#define _GNU_SOURCE 1
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <arpa/nameser.h>
#include <resolv.h>
#include <netdb.h>

/* Append one A record for the compressed owner at offset 12. */
static int add_a(unsigned char *p, const unsigned char *addr, unsigned ttl)
{
  p[0] = 0xc0; p[1] = 0x0c;
  ns_put16(ns_t_a, p + 2);
  ns_put16(ns_c_in, p + 4);
  ns_put32(ttl, p + 6);
  ns_put16(4, p + 10);
  memcpy(p + 12, addr, 4);
  return 16;
}

/* Build a reply in place, DISCARDING EVERYTHING AFTER THE QUESTION.
 *
 * THAT TRUNCATION IS NOT TIDINESS -- IT IS WHY THIS TEST MEASURES ANYTHING.
 * glibc's res_send() appends an EDNS0 OPT record to the ADDITIONAL section
 * even though res_mkquery() does not, so a reply built by appending after the
 * received bytes puts the A record in the additional section and leaves the
 * OPT sitting in the answer section. ns_parserr() then returns the OPT --
 * successfully, type 41, rdlength 0 -- and the row prints no address while
 * every return code still says the lookup worked. The first draft did exactly
 * that and read as "the parser is broken" for both compilers at once.
 * Rebuilding from the end of the QUESTION makes the reply identical whether
 * or not the client sent EDNS, which is the only way pxx and glibc can be
 * compared here at all. */
static int make_reply(unsigned char *buf, int qlen, int rcode,
                      const unsigned char *addr)
{
  int namelen = dn_skipname(buf + 12, buf + qlen);
  int n;
  if (namelen < 0) return qlen;
  n = 12 + namelen + 4;              /* header + qname + qtype + qclass */
  buf[2] = 0x81;                     /* QR + RD */
  buf[3] = (unsigned char)(0x80 | (rcode & 0xf));   /* RA + rcode */
  ns_put16(1, buf + 4);              /* qdcount */
  ns_put16(0, buf + 8);              /* nscount */
  ns_put16(0, buf + 10);             /* arcount -- drops any OPT */
  if (addr) {
    n += add_a(buf + n, addr, 60);
    ns_put16(1, buf + 6);            /* ancount */
  } else {
    ns_put16(0, buf + 6);
  }
  return n;
}

static void server(int s)
{
  unsigned char buf[NS_PACKETSZ];
  struct sockaddr_in from;
  socklen_t fl;
  static const unsigned char real[4]  = { 10, 1, 2, 3 };
  static const unsigned char decoy[4] = { 6, 6, 6, 6 };
  int served = 0;

  while (served < 8) {
    int n, r;
    char qname[NS_MAXDNAME];
    fl = sizeof from;
    n = (int)recvfrom(s, buf, sizeof buf, 0, (struct sockaddr *)&from, &fl);
    if (n < NS_HFIXEDSZ) continue;
    served++;
    if (ns_name_uncompress(buf, buf + n, buf + 12, qname, sizeof qname) < 0)
      continue;

    if (strncmp(qname, "nx.", 3) == 0) {
      r = make_reply(buf, n, ns_r_nxdomain, 0);
      sendto(s, buf, (size_t)r, 0, (struct sockaddr *)&from, fl);
    } else if (strncmp(qname, "spoof.", 6) == 0) {
      unsigned char bad[NS_PACKETSZ];
      memcpy(bad, buf, (size_t)n);
      /* Right shape, right source, WRONG id. */
      ns_put16((uint16_t)(ns_get16(buf) ^ 0xffff), bad);
      r = make_reply(bad, n, ns_r_noerror, decoy);
      sendto(s, bad, (size_t)r, 0, (struct sockaddr *)&from, fl);
      r = make_reply(buf, n, ns_r_noerror, real);
      sendto(s, buf, (size_t)r, 0, (struct sockaddr *)&from, fl);
    } else if (strncmp(qname, "notresp.", 8) == 0) {
      unsigned char bad[NS_PACKETSZ];
      memcpy(bad, buf, (size_t)n);
      r = make_reply(bad, n, ns_r_noerror, decoy);
      bad[2] &= (unsigned char)~0x80;     /* clear QR: still a QUESTION */
      sendto(s, bad, (size_t)r, 0, (struct sockaddr *)&from, fl);
      r = make_reply(buf, n, ns_r_noerror, real);
      sendto(s, buf, (size_t)r, 0, (struct sockaddr *)&from, fl);
    } else {
      r = make_reply(buf, n, ns_r_noerror, real);
      sendto(s, buf, (size_t)r, 0, (struct sockaddr *)&from, fl);
    }
  }
}

static void ask(const char *name)
{
  unsigned char ans[NS_PACKETSZ];
  ns_msg h;
  ns_rr rr;
  char astr[64];
  int n, he;

  h_errno = 0;
  n = res_query(name, ns_c_in, ns_t_a, ans, (int)sizeof ans);
  he = h_errno;
  printf("%-12s rc=%s h_errno=%d", name, n > 0 ? "ok" : "fail", he);
  if (n > 0 && ns_initparse(ans, n, &h) == 0 &&
      ns_msg_count(h, ns_s_an) > 0 && ns_parserr(&h, ns_s_an, 0, &rr) == 0 &&
      ns_rr_rdlen(rr) == 4) {
    inet_ntop(AF_INET, ns_rr_rdata(rr), astr, sizeof astr);
    printf(" addr=%s", astr);
  }
  printf("\n");
}

int main(void)
{
  int s;
  struct sockaddr_in sa;
  socklen_t sl = sizeof sa;
  pid_t pid;

  s = socket(AF_INET, SOCK_DGRAM, 0);
  if (s < 0) { perror("socket"); return 2; }
  memset(&sa, 0, sizeof sa);
  sa.sin_family = AF_INET;
  sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  sa.sin_port = 0;                    /* let the kernel pick */
  if (bind(s, (struct sockaddr *)&sa, sizeof sa) != 0) { perror("bind"); return 2; }
  if (getsockname(s, (struct sockaddr *)&sa, &sl) != 0) { perror("getsockname"); return 2; }

  pid = fork();
  if (pid < 0) { perror("fork"); return 2; }
  if (pid == 0) { server(s); _exit(0); }
  close(s);

  /* res_init() FIRST, THEN OVERRIDE. Writing nsaddr_list before res_init()
     would be undone by it -- and clearing RES_INIT afterwards would make the
     next res_query() re-read /etc/resolv.conf and ask the real network.
     busybox's nslookup does exactly this sequence for the same reason. */
  res_init();
  _res.nscount = 1;
  _res.nsaddr_list[0] = sa;
  _res.nsaddr_list[0].sin_family = AF_INET;
  _res.retrans = 1;
  _res.retry = 1;
  _res.options &= ~(unsigned long)RES_DNSRCH;
  _res.options &= ~(unsigned long)RES_DEFNAMES;

  ask("good.example.com");
  ask("nx.example.com");
  ask("spoof.example.com");
  ask("notresp.example.com");

  kill(pid, SIGTERM);
  waitpid(pid, 0, 0);
  return 0;
}
