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
#include <stdio.h>
#include <string.h>
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
static int serv_parse(char *line) {
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
  while (na < SERV_ALIAS_MAX) {
    while (*p == ' ' || *p == '\t') p++;
    if (*p == '\0' || *p == '\n') break;
    serv_aliases[na++] = p;
    while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;
    if (*p) *p++ = '\0';
  }
  serv_aliases[na] = 0;

  serv_ent.s_name = name;
  serv_ent.s_aliases = serv_aliases;
  serv_ent.s_port = (int)htons((unsigned short)atoi(portstr));  /* NETWORK order */
  serv_ent.s_proto = proto;
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
    if (serv_parse(serv_line)) return &serv_ent;
  }
  return 0;
}

static int serv_proto_ok(const char *proto) {
  return proto == 0 || strcmp(proto, serv_ent.s_proto) == 0;
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
