/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: h_errno, hstrerror/herror, and the /etc/services lookups.
 *
 * The resolver half of <netdb.h> -- gethostbyname/getaddrinfo live in
 * src/netinet/in.c beside the socket layer they share types with; these do not
 * touch the network at all.
 *
 * h_errno IS A REAL VARIABLE, NOT A MACRO OVER errno. They report different
 * things: errno carries the last syscall's failure, h_errno the last lookup's,
 * and the two are set by different code at different times. A program that
 * prints strerror(errno) after a failed gethostbyname usually prints
 * "Success", because the last syscall really did succeed. busybox's
 * libbb/herror_msg.c is written against the real one.
 *
 * THE PORT IN A servent IS IN NETWORK BYTE ORDER. That is the struct's
 * contract and it is the classic place an htons() gets applied twice: the
 * field is already big-endian, so `htons(sp->s_port)' byte-swaps a correct
 * value into a wrong one on a little-endian box and into a correct one on a
 * big-endian box -- which is how this survives testing.
 *
 * /etc/services is parsed the way pwd.c and grp.c parse their files: NO NSS
 * (a libc-free runtime cannot dlopen a name-service module), and a line too
 * long to hold is SKIPPED rather than truncated, since a truncated line yields
 * a plausible wrong entry.
 *
 * Found attempting busybox rung 2: libbb/xconnect.c (getservbyname for a
 * symbolic port), networking/netstat.c (getservbyport).
 */
#include <netdb.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>   /* strcasecmp: <string.h> brings it only without a standard asked for (a unit with _POSIX_C_SOURCE compiles this too) */
#include <stdlib.h>
#include <netinet/in.h>

int h_errno = 0;

const char *hstrerror(int err) {
  if (err == 0)              return "Resolver Error 0 (no error)";
  if (err == HOST_NOT_FOUND) return "Unknown host";
  if (err == TRY_AGAIN)      return "Host name lookup failure";
  if (err == NO_RECOVERY)    return "Unknown server error";
  if (err == NO_DATA)        return "No address associated with name";
  return "Unknown resolver error";
}

void herror(const char *s) {
  if (s && *s) { fputs(s, stderr); fputs(": ", stderr); }
  fputs(hstrerror(h_errno), stderr);
  fputc('\n', stderr);
}

/* ---- /etc/services -------------------------------------------------------- */

#define SERV_LINE_MAX  1024
#define SERV_ALIAS_MAX 16

static FILE *serv_fp;
static int   serv_stayopen;
static char  serv_line[SERV_LINE_MAX];
static char *serv_aliases[SERV_ALIAS_MAX + 1];
static struct servent serv_ent;

void setservent(int stayopen) {
  if (serv_fp) rewind(serv_fp);
  else serv_fp = fopen("/etc/services", "r");
  serv_stayopen = stayopen;
}

void endservent(void) {
  if (serv_fp) fclose(serv_fp);
  serv_fp = 0;
  serv_stayopen = 0;
}

/* Split one line in place. Returns 0 when it is a comment, blank, or malformed
   -- the caller simply reads on, which is what makes a bad line invisible
   rather than fatal. */
static int serv_parse(char *line, struct servent *out, char **al, int almax) {
  char *p = line, *name, *portstr, *slash, *proto;
  int na = 0;

  p = strchr(line, '#');
  if (p) *p = '\0';
  p = line;
  while (*p == ' ' || *p == '\t' || *p == '\n') p++;
  if (*p == '\0') return 0;

  name = p;
  while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;
  if (*p == '\0') return 0;
  *p++ = '\0';
  while (*p == ' ' || *p == '\t') p++;
  if (*p == '\0' || *p == '\n') return 0;

  portstr = p;
  while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;
  if (*p) *p++ = '\0';

  slash = strchr(portstr, '/');
  if (!slash) return 0;             /* "port/proto" is the whole format */
  *slash = '\0';
  proto = slash + 1;
  if (*proto == '\0') return 0;

  /* Whatever is left on the line is aliases. */
  while (na < almax) {
    while (*p == ' ' || *p == '\t') p++;
    if (*p == '\0' || *p == '\n') break;
    al[na++] = p;
    while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;
    if (*p) *p++ = '\0';
  }
  al[na] = 0;

  out->s_name = name;
  out->s_aliases = al;
  out->s_port = (int)htons((unsigned short)atoi(portstr));  /* NETWORK order */
  out->s_proto = proto;
  return 1;
}

struct servent *getservent(void) {
  if (!serv_fp) {
    serv_fp = fopen("/etc/services", "r");
    if (!serv_fp) return 0;
  }
  while (fgets(serv_line, (int)sizeof serv_line, serv_fp)) {
    /* A line that did not fit has no newline: drain and skip it, so its tail
       is never parsed as a fresh entry. */
    if (!strchr(serv_line, '\n')) {
      int c;
      while ((c = fgetc(serv_fp)) != '\n' && c != EOF) { }
      continue;
    }
    if (serv_parse(serv_line, &serv_ent, serv_aliases, SERV_ALIAS_MAX)) return &serv_ent;
  }
  return 0;
}

static int serv_proto_ok(const char *proto) {
  return proto == 0 || strcmp(proto, serv_ent.s_proto) == 0;
}

/* getservbyname_r: no static touched, so two threads can look up a service at
   once. NOT a wrapper pair with the plain form and not a candidate to become
   one -- see pwd.c's block comment for the contract difference (plain SKIPS an
   over-long line, _r must answer ERANGE), and the ALIAS array here is grp.c's
   second reason: the plain form has a dedicated SERV_ALIAS_MAX table while
   this one carves the array out of the caller's buffer, so routing the plain
   one through here would silently shorten a service's alias list.

   `buf' must therefore hold the line AND (aliases + 1) pointers. The alias
   array is placed after the line, aligned up; if there is not room for even
   the terminating NULL that is ERANGE, never "a service with no aliases". */
static int serv_match(const struct servent *e, const char *name,
                      const char *proto) {
  int i;
  if (proto && strcmp(proto, e->s_proto) != 0) return 0;
  if (strcmp(name, e->s_name) == 0) return 1;
  for (i = 0; e->s_aliases[i]; i++)
    if (strcmp(name, e->s_aliases[i]) == 0) return 1;
  return 0;
}

int getservbyname_r(const char *name, const char *proto,
                    struct servent *result_buf, char *buf, size_t buflen,
                    struct servent **result) {
  FILE *fp;

  if (result) *result = 0;
  if (!name || !result_buf || !buf || !result || buflen == 0) return EINVAL;

  fp = fopen("/etc/services", "r");
  if (!fp) return ENOENT;

  while (fgets(buf, (int)buflen, fp)) {
    char **al;
    size_t len, off, pad, sz;
    int almax;

    /* Two causes for a missing newline and they need different answers -- too
       small a buffer (ERANGE, the caller retries) versus a final line with no
       trailing newline (ordinary, parse it). */
    if (!strchr(buf, '\n') && !feof(fp)) { fclose(fp); return ERANGE; }

    len = strlen(buf);
    sz  = sizeof(char *);
    off = len + 1;
    pad = (sz - (off % sz)) % sz;
    if (off + pad + sz > buflen) { fclose(fp); return ERANGE; }

    al    = (char **)(void *)(buf + off + pad);
    almax = (int)((buflen - (off + pad)) / sz) - 1;   /* -1 for the NULL slot */
    if (almax < 0) { fclose(fp); return ERANGE; }

    if (!serv_parse(buf, result_buf, al, almax)) continue;
    if (serv_match(result_buf, name, proto)) {
      fclose(fp);
      *result = result_buf;
      return 0;
    }
  }

  fclose(fp);
  return 0;                          /* not found: 0 with *result == NULL */
}

struct servent *getservbyname(const char *name, const char *proto) {
  int keep = serv_stayopen;
  struct servent *e, *hit = 0;
  if (!name) return 0;
  setservent(keep);
  while ((e = getservent()) != 0) {
    int i;
    if (!serv_proto_ok(proto)) continue;
    if (strcmp(name, e->s_name) == 0) { hit = e; break; }
    for (i = 0; e->s_aliases[i]; i++)
      if (strcmp(name, e->s_aliases[i]) == 0) { hit = e; break; }
    if (hit) break;
  }
  /* Closing the stream is safe with a hit in hand: the strings point into
     serv_line, a static buffer that endservent does not touch. It is the NEXT
     getservent that invalidates them, which is glibc's contract too. */
  if (!keep) endservent();
  return hit;
}

struct servent *getservbyport(int port, const char *proto) {
  int keep = serv_stayopen;
  struct servent *e, *hit = 0;
  setservent(keep);
  while ((e = getservent()) != 0) {
    if (!serv_proto_ok(proto)) continue;
    if (e->s_port == port) { hit = e; break; }   /* both in NETWORK order */
  }
  if (!keep) endservent();
  return hit;
}

/* ---- names to IPv4 addresses: /etc/hosts, then DNS ------------------------
 *
 * __pxx_resolve4 is what getaddrinfo and gethostbyname (src/netinet/in.c) use
 * for a node that is not a dotted quad. /etc/hosts first, as glibc's default
 * `hosts: files dns' does, then an A query through the stub resolver
 * (src/resolv.c, /etc/resolv.conf's servers, its search list). Up to `max'
 * addresses, network order, into `out'; `canon' (256 bytes, may be NULL) gets
 * the name the answer is for. Returns the count, or 0 with h_errno set.
 *
 * Until 2026-11-26 every name was EAI_NONAME, so on a pxx-built userland
 * `wget http://host/', `ping host' and `hostname -i' failed while the stub
 * resolver to answer them sat in the same runtime.
 * bug-c-crtl-getaddrinfo-resolves-no-names */
#include <resolv.h>
#include <arpa/nameser.h>
#include <arpa/inet.h>

static int pxx_hosts_lookup(const char *name, unsigned int *out, int max, char *canon) {
  FILE *f = fopen("/etc/hosts", "r");
  char line[512];
  int n = 0;
  if (!f) return 0;
  while (n < max && fgets(line, sizeof line, f)) {
    char *p = line, *addr, *w, *first;
    struct in_addr a;
    int hit = 0;
    char *hash = strchr(p, '#');
    if (hash) *hash = 0;
    addr = strtok(p, " \t\r\n");
    if (!addr || inet_pton(AF_INET, addr, &a) != 1) continue;   /* IPv6 lines too */
    first = 0;
    while ((w = strtok(0, " \t\r\n")) != 0) {
      if (!first) first = w;
      if (strcasecmp(w, name) == 0) hit = 1;
    }
    if (hit) {
      if (n == 0 && canon && first) { strncpy(canon, first, 255); canon[255] = 0; }
      out[n++] = a.s_addr;
    }
  }
  fclose(f);
  return n;
}

int __pxx_resolve4(const char *name, unsigned int *out, int max, char *canon) {
  unsigned char ans[1500];
  ns_msg m;
  ns_rr rr;
  int len, i, n;
  if (canon) canon[0] = 0;
  n = pxx_hosts_lookup(name, out, max, canon);
  if (n > 0) return n;
  len = res_search(name, ns_c_in, ns_t_a, ans, sizeof ans);
  if (len <= 0 || ns_initparse(ans, len, &m) < 0) { h_errno = HOST_NOT_FOUND; return 0; }
  for (i = 0; i < ns_msg_count(m, ns_s_an) && n < max; i++) {
    if (ns_parserr(&m, ns_s_an, i, &rr) < 0) break;
    if (ns_rr_type(rr) != ns_t_a || ns_rr_rdlen(rr) != 4) continue;   /* CNAMEs are steps */
    memcpy(&out[n], ns_rr_rdata(rr), 4);
    if (n == 0 && canon) { strncpy(canon, ns_rr_name(rr), 255); canon[255] = 0; }
    n++;
  }
  if (n == 0) h_errno = NO_DATA;
  return n;
}
