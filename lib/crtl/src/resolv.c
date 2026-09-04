/* SPDX-License-Identifier: Zlib */
/*
 * The DNS resolver: state, query construction, and the send/retry loop.
 *
 * WHAT THIS IS NOT. It is a STUB RESOLVER -- it asks a configured server a
 * question and reads the answer. It does not walk the delegation chain from
 * the root, it does not cache, and it does not validate DNSSEC. That is the
 * same contract glibc's res_* has, and it is worth stating because "resolver"
 * is used for both things and the difference is every security property.
 *
 * NO ANSWER IS TRUSTED BECAUSE IT ARRIVED. res_nsend() checks the query id
 * and that the reply is a response before accepting a datagram, because a UDP
 * socket will happily hand over a packet from anyone who guessed the port.
 * That is a spoofing defence with a known strength -- 16 bits of id plus the
 * ephemeral port -- and not a guarantee; a caller that needs one wants TCP
 * (RES_USEVC) or a validating resolver, and this file cannot provide either.
 *
 * A TRUNCATED REPLY IS RETRIED OVER TCP unless RES_IGNTC. Accepting the
 * truncated one is the tempting shortcut and it is wrong in a specific way:
 * the answer section is CUT, so a lookup with four A records silently
 * returns two, and the caller cannot tell that from a host with two
 * addresses.
 *
 * /etc/resolv.conf IS THE ONLY SOURCE. No NSS (a libc-free runtime cannot
 * dlopen a name-service module -- src/netdb.c says the same), no $LOCALDOMAIN,
 * no $RES_OPTIONS. Those produce a DIFFERENT answer rather than a failure,
 * so <resolv.h> names them.
 */

#include <resolv.h>
#include <arpa/nameser.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/random.h>
#include <sys/time.h>
#include <netdb.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <poll.h>
#include <time.h>

/* ONE PROCESS-WIDE STATE, NOT ONE PER THREAD. See the note in <resolv.h>:
   glibc's `_res' is thread-local and this cannot be until the object writer
   grows TLS symbols. The accessor is kept so the change lands here alone. */
static struct __res_state res_state_storage;

struct __res_state *__res_state(void)
{
  return &res_state_storage;
}

unsigned int res_randomid(void)
{
  unsigned short v = 0;
  /* getrandom() FIRST AND THE CLOCK ONLY AS A FALLBACK. A query id drawn
     from the clock is guessable to within a handful of values by anyone who
     knows roughly when the query went out, which is exactly the attacker
     this id exists to stop. The fallback is here so a kernel without
     getrandom still resolves, and it is weaker on purpose rather than by
     accident. */
  if (getrandom(&v, sizeof v, 0) == (ssize_t)sizeof v)
    return (unsigned int)v;
  {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (unsigned int)((ts.tv_nsec ^ (ts.tv_sec << 5) ^ getpid()) & 0xffff);
  }
}

static void res_setdefaults(res_state statp)
{
  memset(statp, 0, sizeof *statp);
  statp->retrans = RES_TIMEOUT;
  statp->retry   = RES_DFLRETRY;
  statp->options = RES_DEFAULT;
  statp->ndots   = 1;
  statp->id      = (unsigned short)res_randomid();
  statp->_vcsock = -1;
}

/* The search list points into this one buffer, so freeing it would invalidate
   every dnsrch[] entry at once. It is deliberately never freed: the state is
   a single static object with process lifetime, and a res_init() that
   reallocated it would leave a caller's saved `dnsrch[i]' dangling. */
static char res_srchbuf[1024];

static void res_addsearch(res_state statp, const char *name, size_t *used)
{
  size_t n = strlen(name);
  int i;
  for (i = 0; i < MAXDNSRCH && statp->dnsrch[i]; i++)
    ;
  if (i >= MAXDNSRCH) return;
  if (*used + n + 1 > sizeof res_srchbuf) return;
  memcpy(res_srchbuf + *used, name, n + 1);
  statp->dnsrch[i] = res_srchbuf + *used;
  statp->dnsrch[i + 1] = 0;
  *used += n + 1;
}

int res_ninit(res_state statp)
{
  FILE *f;
  char line[512];
  size_t used = 0;

  res_setdefaults(statp);

  f = fopen("/etc/resolv.conf", "r");
  if (f) {
    while (fgets(line, sizeof line, f)) {
      char *p = line, *tok;
      while (*p == ' ' || *p == '\t') p++;
      if (*p == '#' || *p == ';' || *p == '\n' || *p == '\0') continue;
      /* Trim at the first comment or newline, then split on whitespace. */
      for (tok = p; *tok; tok++)
        if (*tok == '\n' || *tok == '#' || *tok == ';') { *tok = '\0'; break; }

      if (strncmp(p, "nameserver", 10) == 0 && (p[10] == ' ' || p[10] == '\t')) {
        char *a = p + 10;
        while (*a == ' ' || *a == '\t') a++;
        {
          char *e = a;
          while (*e && *e != ' ' && *e != '\t') e++;
          *e = '\0';
        }
        if (statp->nscount < MAXNS) {
          struct in_addr in;
          if (inet_pton(AF_INET, a, &in) == 1) {
            statp->nsaddr_list[statp->nscount].sin_family = AF_INET;
            statp->nsaddr_list[statp->nscount].sin_port = htons(NS_DEFAULTPORT);
            statp->nsaddr_list[statp->nscount].sin_addr = in;
            statp->nscount++;
          }
          /* AN IPv6 NAMESERVER IS PARSED AND THEN DROPPED, and that is
             recorded rather than hidden: nsaddr_list is an array of
             sockaddr_in and cannot hold one. glibc keeps them in
             _u._ext.nsaddrs, which needs allocation this file does not do.
             A resolv.conf with ONLY IPv6 servers therefore leaves nscount 0
             and every lookup fails -- visibly, rather than by asking the
             wrong server. */
        }
      } else if ((strncmp(p, "domain", 6) == 0 && (p[6] == ' ' || p[6] == '\t')) ||
                 (strncmp(p, "search", 6) == 0 && (p[6] == ' ' || p[6] == '\t'))) {
        int is_search = (p[0] == 's');
        char *a = p + 6;
        while (*a == ' ' || *a == '\t') a++;
        if (!is_search) {
          char *e = a;
          while (*e && *e != ' ' && *e != '\t') e++;
          *e = '\0';
          snprintf(statp->defdname, sizeof statp->defdname, "%s", a);
          /* THE LAST `domain' OR `search' LINE WINS AND IT REPLACES, NOT
             APPENDS. Two `search' lines in one file is a configuration
             mistake whose effect surprises people; matching the documented
             behaviour is the only defensible answer. */
          memset(statp->dnsrch, 0, sizeof statp->dnsrch);
          used = 0;
          if (*a) res_addsearch(statp, a, &used);
        } else {
          memset(statp->dnsrch, 0, sizeof statp->dnsrch);
          used = 0;
          while (*a) {
            char *e = a;
            while (*e && *e != ' ' && *e != '\t') e++;
            if (*e) { *e = '\0'; e++; }
            if (*a) res_addsearch(statp, a, &used);
            while (*e == ' ' || *e == '\t') e++;
            a = e;
          }
          if (statp->dnsrch[0])
            snprintf(statp->defdname, sizeof statp->defdname, "%s",
                     statp->dnsrch[0]);
        }
      } else if (strncmp(p, "options", 7) == 0 &&
                 (p[7] == ' ' || p[7] == '\t')) {
        char *a = p + 7;
        while (*a) {
          char *e = a;
          while (*e && *e != ' ' && *e != '\t') e++;
          if (*e) { *e = '\0'; e++; }
          if (strncmp(a, "ndots:", 6) == 0) {
            int n = atoi(a + 6);
            if (n < 0) n = 0;
            if (n > RES_MAXNDOTS) n = RES_MAXNDOTS;
            statp->ndots = (unsigned)n;
          } else if (strncmp(a, "timeout:", 8) == 0) {
            int n = atoi(a + 8);
            if (n > 0) statp->retrans = n > RES_MAXRETRANS ? RES_MAXRETRANS : n;
          } else if (strncmp(a, "attempts:", 9) == 0) {
            int n = atoi(a + 9);
            if (n > 0) statp->retry = n > RES_MAXRETRY ? RES_MAXRETRY : n;
          } else if (strcmp(a, "rotate") == 0) {
            statp->options |= RES_ROTATE;
          } else if (strcmp(a, "use-vc") == 0) {
            statp->options |= RES_USEVC;
          } else if (strcmp(a, "no-tld-query") == 0) {
            statp->options |= RES_NOTLDQUERY;
          }
          while (*a) a++;
          a = e;
        }
      }
    }
    fclose(f);
  }

  /* NO NAMESERVER LINE MEANS THE LOCAL ONE, which is what every stub resolver
     does and what a container with an empty resolv.conf relies on. */
  if (statp->nscount == 0) {
    statp->nsaddr_list[0].sin_family = AF_INET;
    statp->nsaddr_list[0].sin_port = htons(NS_DEFAULTPORT);
    statp->nsaddr_list[0].sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    statp->nscount = 1;
  }
  statp->options |= RES_INIT;
  return 0;
}

int res_init(void)
{
  /* RES_INIT IS A RE-ENTRY GUARD. Returning early when it is set is glibc's
     behaviour and callers work around it by clearing the bit or writing
     nsaddr_list directly -- busybox's nslookup does the latter. */
  if (res_state_storage.options & RES_INIT) return 0;
  return res_ninit(&res_state_storage);
}

void res_nclose(res_state statp)
{
  if (statp->_vcsock >= 0) {
    close(statp->_vcsock);
    statp->_vcsock = -1;
  }
}

void res_close(void) { res_nclose(&res_state_storage); }

int res_nmkquery(res_state statp, int op, const char *dname, int cls, int type,
                 const unsigned char *data, int datalen,
                 const unsigned char *newrr, unsigned char *buf, int buflen)
{
  unsigned char *cp = buf;
  int n;

  (void)data; (void)datalen; (void)newrr;
  if (!dname || !buf || buflen < NS_HFIXEDSZ) { errno = EINVAL; return -1; }

  memset(buf, 0, NS_HFIXEDSZ);
  ns_put16(statp->id, cp);
  /* THE ID IS ADVANCED HERE, NOT IN res_send, so two queries built before
     either is sent still differ. A resolver that assigned the id at send
     time would give both the same one, and the second reply would be
     accepted for the first query. */
  statp->id = (unsigned short)res_randomid();
  cp += NS_INT16SZ;
  {
    uint16_t flags = (uint16_t)((op & 0xf) << 11);
    if (statp->options & RES_RECURSE) flags |= 0x0100;   /* RD */
    ns_put16(flags, cp);
  }
  cp += NS_INT16SZ;
  ns_put16(1, cp); cp += NS_INT16SZ;      /* qdcount */
  ns_put16(0, cp); cp += NS_INT16SZ;      /* ancount */
  ns_put16(0, cp); cp += NS_INT16SZ;      /* nscount */
  ns_put16(0, cp); cp += NS_INT16SZ;      /* arcount */

  /* ns_name_pton() ANSWERS 0 OR 1 -- "was this fully qualified" -- AND NOT A
     LENGTH. Using its return value as one advances the cursor by a byte and
     builds a question section out of the wrong bytes, and it does it
     SILENTLY: the packet is still the right size, so the server answers with
     a FORMERR rather than anything naming the cause. The length has to be
     walked. */
  if (ns_name_pton(dname, cp, (size_t)(buflen - (cp - buf))) < 0) {
    errno = EMSGSIZE; return -1;
  }
  {
    unsigned char *q = cp;
    while (*q != 0) {
      if ((*q & NS_CMPRSFLGS) != 0) { errno = EMSGSIZE; return -1; }
      q += *q + 1;
      if (q >= buf + buflen) { errno = EMSGSIZE; return -1; }
    }
    cp = q + 1;
  }
  if (cp + NS_QFIXEDSZ > buf + buflen) { errno = EMSGSIZE; return -1; }
  ns_put16((uint16_t)type, cp); cp += NS_INT16SZ;
  ns_put16((uint16_t)cls,  cp); cp += NS_INT16SZ;
  return (int)(cp - buf);
}

int res_mkquery(int op, const char *dname, int cls, int type,
                const unsigned char *data, int datalen,
                const unsigned char *newrr, unsigned char *buf, int buflen)
{
  if (res_init() < 0) return -1;
  return res_nmkquery(&res_state_storage, op, dname, cls, type,
                      data, datalen, newrr, buf, buflen);
}

/* One TCP attempt. Returns the reply length, or -1. */
static int res_send_vc(res_state statp, const struct sockaddr_in *nsa,
                       const unsigned char *msg, int msglen,
                       unsigned char *answer, int anslen)
{
  int s, got = 0, want;
  unsigned char len[2];

  s = socket(AF_INET, SOCK_STREAM, 0);
  if (s < 0) return -1;
  if (connect(s, (const struct sockaddr *)nsa, sizeof *nsa) < 0) {
    close(s); return -1;
  }
  /* OVER TCP THE MESSAGE IS PRECEDED BY A 2-BYTE LENGTH. Forgetting it is
     the classic DNS-over-TCP bug: the server reads the first two bytes of
     the query id as a length and waits forever for a message that size. */
  len[0] = (unsigned char)(msglen >> 8);
  len[1] = (unsigned char)(msglen & 0xff);
  if (write(s, len, 2) != 2 || write(s, msg, (size_t)msglen) != msglen) {
    close(s); return -1;
  }
  while (got < 2) {
    ssize_t n = read(s, len + got, (size_t)(2 - got));
    if (n <= 0) { close(s); return -1; }
    got += (int)n;
  }
  want = (len[0] << 8) | len[1];
  if (want > anslen) want = anslen;   /* the caller's buffer is the cap */
  got = 0;
  while (got < want) {
    ssize_t n = read(s, answer + got, (size_t)(want - got));
    if (n <= 0) { close(s); return -1; }
    got += (int)n;
  }
  close(s);
  return got;
}

int res_nsend(res_state statp, const unsigned char *msg, int msglen,
              unsigned char *answer, int anslen)
{
  int try_, ns;

  if (!(statp->options & RES_INIT) && res_ninit(statp) < 0) return -1;
  if (msglen < NS_HFIXEDSZ) { errno = EINVAL; return -1; }
  if (statp->nscount <= 0) { errno = ECONNREFUSED; h_errno = NO_RECOVERY; return -1; }

  if (statp->options & RES_USEVC) {
    for (try_ = 0; try_ < statp->retry; try_++)
      for (ns = 0; ns < statp->nscount; ns++) {
        int n = res_send_vc(statp, &statp->nsaddr_list[ns], msg, msglen,
                            answer, anslen);
        if (n >= NS_HFIXEDSZ) return n;
      }
    errno = ETIMEDOUT;
    h_errno = TRY_AGAIN;
    return -1;
  }

  for (try_ = 0; try_ < statp->retry; try_++) {
    for (ns = 0; ns < statp->nscount; ns++) {
      int s, n;
      struct pollfd pfd;

      s = socket(AF_INET, SOCK_DGRAM, 0);
      if (s < 0) continue;
      /* connect() ON A UDP SOCKET IS NOT A HANDSHAKE -- it fixes the peer, so
         the kernel drops datagrams from anyone else before they reach us.
         That is one of the two spoofing filters here; the id check below is
         the other, and neither is sufficient alone. */
      if (connect(s, (const struct sockaddr *)&statp->nsaddr_list[ns],
                  sizeof statp->nsaddr_list[ns]) < 0) {
        close(s); continue;
      }
      if (write(s, msg, (size_t)msglen) != msglen) { close(s); continue; }

      for (;;) {
        pfd.fd = s;
        pfd.events = POLLIN;
        pfd.revents = 0;
        n = poll(&pfd, 1, statp->retrans * 1000);
        if (n <= 0) { n = -1; break; }
        n = (int)read(s, answer, (size_t)anslen);
        if (n < NS_HFIXEDSZ) { n = -1; break; }
        /* THE REPLY MUST ANSWER THE QUESTION WE ASKED. A datagram that
           reaches a connected socket already came from the server's address,
           but the id check is what makes a blind off-path forgery need to
           guess it. A mismatched id is DISCARDED AND THE WAIT CONTINUES --
           not treated as a failure -- because giving up would let one stray
           packet cancel a query that is still going to be answered. */
        if (ns_get16(answer) != ns_get16(msg)) continue;
        /* QR CLEAR MEANS THIS IS A QUERY, NOT AN ANSWER, and glibc does
           NOT make this check -- measured, not assumed: a decoy with the
           right id and QR clear is accepted there and skipped here. Chosen
           divergence, recorded in known-incompat/incompat-b-crtls-dns-
           parser-refuses-two-malformed-packets-glibc-accepts. */
        if (!(answer[2] & 0x80)) continue;
        break;
      }
      close(s);
      if (n < 0) continue;

      /* TC: the reply did not fit in a datagram. Retrying over TCP is the
         only way to see the rest; accepting this one silently returns a
         SHORTER answer section, which reads as a host with fewer addresses. */
      if ((answer[2] & 0x02) && !(statp->options & RES_IGNTC)) {
        int m = res_send_vc(statp, &statp->nsaddr_list[ns], msg, msglen,
                            answer, anslen);
        if (m >= NS_HFIXEDSZ) return m;
      }
      return n;
    }
  }
  errno = ETIMEDOUT;
  h_errno = TRY_AGAIN;
  return -1;
}

int res_send(const unsigned char *msg, int msglen,
             unsigned char *answer, int anslen)
{
  if (res_init() < 0) return -1;
  return res_nsend(&res_state_storage, msg, msglen, answer, anslen);
}

int res_nquery(res_state statp, const char *dname, int cls, int type,
               unsigned char *answer, int anslen)
{
  unsigned char buf[NS_PACKETSZ];
  int n;

  n = res_nmkquery(statp, ns_o_query, dname, cls, type, 0, 0, 0,
                   buf, (int)sizeof buf);
  if (n < 0) { h_errno = NO_RECOVERY; return -1; }
  n = res_nsend(statp, buf, n, answer, anslen);
  if (n < 0) { h_errno = TRY_AGAIN; return -1; }

  /* THE RCODE IS AN ANSWER, NOT AN ERROR, and the distinction is the whole
     reason h_errno exists next to errno. NXDOMAIN means the server answered
     and the name does not exist; a timeout means nobody answered. A caller
     that treats both as -1 without reading h_errno retries a name that will
     never resolve. */
  {
    int rcode  = answer[3] & 0xf;
    int ancount = ns_get16(answer + 6);
    if (rcode != ns_r_noerror || ancount == 0) {
      switch (rcode) {
      case ns_r_nxdomain: h_errno = HOST_NOT_FOUND; break;
      case ns_r_servfail: h_errno = TRY_AGAIN;      break;
      case ns_r_noerror:  h_errno = NO_DATA;        break;
      default:            h_errno = NO_RECOVERY;    break;
      }
      return -1;
    }
  }
  return n;
}

int res_query(const char *dname, int cls, int type,
              unsigned char *answer, int anslen)
{
  if (res_init() < 0) return -1;
  return res_nquery(&res_state_storage, dname, cls, type, answer, anslen);
}

int res_nsearch(res_state statp, const char *dname, int cls, int type,
                unsigned char *answer, int anslen)
{
  char buf[NS_MAXDNAME];
  const char *cp;
  int dots = 0, n, i, saved_herrno;

  if (!(statp->options & RES_INIT) && res_ninit(statp) < 0) return -1;
  for (cp = dname; *cp; cp++) if (*cp == '.') dots++;

  /* THE ndots RULE, AND IT IS AN ORDER RULE RATHER THAN A FILTER. A name with
     at least ndots dots is tried AS GIVEN FIRST and only then through the
     search list; one with fewer is tried through the search list first. Both
     orders eventually try both forms -- what changes is which answer a
     caller gets when both exist, and that is the whole reason "www" can
     resolve differently on two networks. */
  saved_herrno = -1;
  if (dots >= (int)statp->ndots || (cp > dname && cp[-1] == '.')) {
    n = res_nquery(statp, dname, cls, type, answer, anslen);
    if (n > 0) return n;
    saved_herrno = h_errno;
  }

  if ((statp->options & RES_DNSRCH) && !(cp > dname && cp[-1] == '.')) {
    for (i = 0; i < MAXDNSRCH && statp->dnsrch[i]; i++) {
      if (snprintf(buf, sizeof buf, "%s.%s", dname, statp->dnsrch[i])
          >= (int)sizeof buf)
        continue;
      n = res_nquery(statp, buf, cls, type, answer, anslen);
      if (n > 0) return n;
      /* A SERVFAIL OR A TIMEOUT STOPS THE SEARCH; NXDOMAIN CONTINUES IT.
         Walking on after a server failure asks a question the server already
         said it could not answer, once per search domain, and turns one slow
         lookup into six. */
      if (h_errno == TRY_AGAIN || h_errno == NO_RECOVERY) return -1;
    }
  }

  if (dots < (int)statp->ndots && !(cp > dname && cp[-1] == '.')) {
    n = res_nquery(statp, dname, cls, type, answer, anslen);
    if (n > 0) return n;
  }
  if (saved_herrno >= 0) h_errno = saved_herrno;
  return -1;
}

int res_search(const char *dname, int cls, int type,
               unsigned char *answer, int anslen)
{
  if (res_init() < 0) return -1;
  return res_nsearch(&res_state_storage, dname, cls, type, answer, anslen);
}
