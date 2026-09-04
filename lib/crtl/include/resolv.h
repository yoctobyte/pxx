/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <resolv.h> -- the DNS resolver state and the res_* entry points.
 *
 * `_res' IS ONE PROCESS-WIDE STRUCT HERE, NOT ONE PER THREAD, and that is a
 * KNOWN DIVERGENCE rather than an oversight. glibc spells `_res' as
 * `(*__res_state())' precisely so the storage can be thread-local, and this
 * header keeps that spelling so the day it becomes per-thread nothing but
 * __res_state() changes. It cannot be per-thread today for the same reason
 * errno is not: the object writer has no TLS symbols
 * (bug-a-errno-is-one-global-across-all-threads-so-a-thread-reads-another-
 * threads-failure). A threaded program that calls res_init() from two threads
 * shares one nameserver list; a single-threaded one, which is every busybox
 * applet that touches this, is unaffected.
 *
 * THE SEARCH LIST AND THE OPTIONS COME FROM /etc/resolv.conf AND NOTHING
 * ELSE. No NSS, for the reason src/netdb.c gives -- a libc-free runtime
 * cannot dlopen a name-service module -- and no $RES_OPTIONS, no
 * $LOCALDOMAIN. A caller that depends on those gets the file's answer, which
 * is a DIFFERENT answer rather than a failure, so it is named here.
 *
 * res_query() AND res_search() ARE NOT THE SAME FUNCTION AND THE DIFFERENCE
 * IS THE ONE PEOPLE GET WRONG: res_query() asks for exactly the name given;
 * res_search() applies the search list and the ndots rule first. Using
 * res_query() where the caller meant res_search() fails on every unqualified
 * name, and using res_search() where they meant res_query() can silently
 * resolve "www" to "www.example.com" on the wrong network.
 *
 * Found attempting busybox on i386: networking/nslookup.c.
 * bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS
 */
#ifndef _CRTL_RESOLV_H
#define _CRTL_RESOLV_H

#include <stdint.h>
#include <stdio.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/nameser.h>

#define MAXNS             3   /* name servers tracked; the array is fixed  */
#define MAXDFLSRCH        3   /* default domain levels tried               */
#define MAXDNSRCH         6   /* entries in the search path                */
#define MAXRESOLVSORT    10
#define LOCALDOMAINPARTS  2

#define RES_TIMEOUT       5   /* seconds between retries                   */
#define RES_MAXNDOTS     15   /* the ndots field is 4 bits, hence 15       */
#define RES_MAXRETRANS   30
#define RES_MAXRETRY      5
#define RES_DFLRETRY      2
#define RES_MAXTIME   65535   /* "infinity", in milliseconds               */

/* Option flags in _res.options. */
#define RES_INIT        0x00000001  /* SET BY res_init(); see the note below */
#define RES_DEBUG       0x00000002
#define RES_USEVC       0x00000008  /* use TCP rather than UDP               */
#define RES_IGNTC       0x00000020  /* do not retry a truncated reply on TCP */
#define RES_RECURSE     0x00000040  /* set the RD bit in queries             */
#define RES_DEFNAMES    0x00000080  /* append the default domain             */
#define RES_STAYOPEN    0x00000100
#define RES_DNSRCH      0x00000200  /* search up the local domain tree       */
#define RES_ROTATE      0x00004000
#define RES_USE_EDNS0   0x00100000
#define RES_SNGLKUP     0x00200000
#define RES_USE_DNSSEC  0x00800000
#define RES_NOTLDQUERY  0x01000000
#define RES_TRUSTAD     0x04000000
#define RES_NOAAAA      0x08000000

#define RES_DEFAULT (RES_RECURSE | RES_DEFNAMES | RES_DNSRCH)

/* RES_INIT IS THE RE-ENTRY GUARD, NOT A STATUS BIT. res_init() tests it and
   returns immediately when set, which is why a caller that changes
   /etc/resolv.conf and calls res_init() again sees nothing change unless it
   clears the bit first. glibc behaves the same way and busybox's nslookup
   works around it by writing _res.nsaddr_list directly. */

/* RES_USE_INET6 was removed from glibc in 2.25 and is deliberately NOT
   defined. Defining it would let `_res.options |= RES_USE_INET6' compile and
   do nothing -- the exact silent-no-op this runtime refuses elsewhere
   (GLOB_BRACE, FNM_EXTMATCH). nslookup.c has the line commented out for the
   same reason. */

struct __res_state {
  int            retrans;              /* seconds before a retry            */
  int            retry;                /* how many times to retry           */
  unsigned long  options;
  int            nscount;              /* IPv4 servers in nsaddr_list       */
  struct sockaddr_in nsaddr_list[MAXNS];
  unsigned short id;                   /* the next query id                 */
  char          *dnsrch[MAXDNSRCH + 1];/* the search list, NULL-terminated  */
  char           defdname[256];        /* the default domain                */
  unsigned long  pfcode;
  unsigned       ndots:4;              /* dots needed to try the name as-is */
  unsigned       nsort:4;
  unsigned       ipv6_unavail:1;
  unsigned       unused:23;
  struct {
    struct in_addr addr;
    uint32_t       mask;
  } sort_list[MAXRESOLVSORT];
  void          *__unused_qhook;
  void          *__unused_rhook;
  int            res_h_errno;          /* the last error for this context   */
  int            _vcsock;              /* PRIVATE: the TCP socket           */
  unsigned int   _flags;               /* PRIVATE                           */
  /* THE UNION IS PART OF THE ABI IN PRACTICE, not an implementation detail:
     real code -- nslookup.c:151 among it -- reads _u._ext.nsaddrs to find an
     IPv6 nameserver, because nsaddr_list above can only hold IPv4. The `pad'
     arm is what fixes the struct's size, and it is 52 bytes for the reason
     glibc's comment records: it makes the whole thing 512 bytes on i386. */
  union {
    char pad[52];
    struct {
      uint16_t             nscount;
      uint16_t             nsmap[MAXNS];
      int                  nssocks[MAXNS];
      uint16_t             nscount6;
      uint16_t             nsinit;
      struct sockaddr_in6 *nsaddrs[MAXNS];
      unsigned int         __reserved[2];
    } _ext;
  } _u;
};

typedef struct __res_state *res_state;

/* The spelling is glibc's on purpose -- see the header note. */
struct __res_state *__res_state(void);
#define _res (*__res_state())

int  res_init(void);
int  res_ninit(res_state statp);
void res_close(void);
void res_nclose(res_state statp);

int  res_mkquery(int op, const char *dname, int cls, int type,
                 const unsigned char *data, int datalen,
                 const unsigned char *newrr, unsigned char *buf, int buflen);
int  res_nmkquery(res_state statp, int op, const char *dname, int cls, int type,
                  const unsigned char *data, int datalen,
                  const unsigned char *newrr, unsigned char *buf, int buflen);

int  res_send(const unsigned char *msg, int msglen,
              unsigned char *answer, int anslen);
int  res_nsend(res_state statp, const unsigned char *msg, int msglen,
               unsigned char *answer, int anslen);

int  res_query(const char *dname, int cls, int type,
               unsigned char *answer, int anslen);
int  res_nquery(res_state statp, const char *dname, int cls, int type,
                unsigned char *answer, int anslen);

int  res_search(const char *dname, int cls, int type,
                unsigned char *answer, int anslen);
int  res_nsearch(res_state statp, const char *dname, int cls, int type,
                 unsigned char *answer, int anslen);

/* dn_expand() is ns_name_uncompress() under the older name and dn_comp() is
   ns_name_compress(); both are kept because real code spells them either way.
   dn_skipname() steps over a name WITHOUT decoding it, which is the only one
   of the three that is not a rename. */
int  dn_expand(const unsigned char *msg, const unsigned char *eom,
               const unsigned char *src, char *dst, int dstsiz);
int  dn_comp(const char *src, unsigned char *dst, int dstsiz,
             unsigned char **dnptrs, unsigned char **lastdnptr);
int  dn_skipname(const unsigned char *ptr, const unsigned char *eom);

/* A query id. NOT a security guarantee: it is the resolver's spoofing
   defence and it is only as good as the entropy behind it. This one draws
   from getrandom(2) and falls back on the clock, which is weaker; a caller
   that needs a hardened resolver should not be using this one. */
unsigned int res_randomid(void);

#endif /* _CRTL_RESOLV_H */
