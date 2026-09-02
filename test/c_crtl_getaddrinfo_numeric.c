/* SPDX-License-Identifier: Zlib */
/*
 * crtl: getaddrinfo / getnameinfo, the NUMERIC contract.
 *
 * crtl has no DNS client and no NSS to load one from, so a hostname is
 * EAI_NONAME and a reverse lookup never happens. Everything else -- a dotted
 * quad, a NULL node under AI_PASSIVE, a numeric or /etc/services port, and the
 * sockaddr-to-string direction -- must work, because that is every path
 * busybox's libbb/xconnect.c takes with an address it was handed literally.
 *
 * THE OLD BODY RETURNED EAI_NONAME FOR EVERYTHING while its comment claimed
 * dotted quads resolved. Row 1 is the row that was failing; rows 2-3 read the
 * resulting sockaddr, because a getaddrinfo that returns 0 and fills nothing
 * passes row 1 on its own.
 *
 * ROW 12 IS THE ONE WITH A WRONG ANSWER AVAILABLE: NI_NAMEREQD asks for a name
 * and says it would rather have nothing than a number. Handing back the dotted
 * quad answers a DIFFERENT question while looking like success -- busybox's
 * xmalloc_sockaddr2host wants the failure -- so it must be EAI_NONAME here.
 *
 * Rows 6/7 pin the AI_PASSIVE asymmetry: a NULL node is the WILDCARD when the
 * caller means to bind and the LOOPBACK when it means to connect. Getting that
 * backwards binds a server to 127.0.0.1 and it answers only itself.
 *
 * Every read is sequenced into its own statement: an argument list has no
 * evaluation order.
 *
 * Every row was diffed against glibc by compiling this same file with gcc.
 * feature-c-corpus-busybox-multi-applet
 */
#include <stdio.h>
#include <string.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>

int main(void) {
  struct addrinfo hint, *r;
  struct sockaddr_in sa;
  char h[NI_MAXHOST], sv[NI_MAXSERV];
  int rc;

  memset(&hint, 0, sizeof(hint));
  hint.ai_family = AF_INET;
  hint.ai_socktype = SOCK_STREAM;

  rc = getaddrinfo("10.1.2.3", "80", &hint, &r);
  printf("1 %d\n", rc);
  if (rc == 0) {
    struct sockaddr_in *p = (struct sockaddr_in *)r->ai_addr;
    rc = (p->sin_family == AF_INET);
    printf("2 %d\n", rc);
    rc = ntohs(p->sin_port);
    printf("3 %d %s\n", rc, inet_ntoa(p->sin_addr));
    rc = (int)r->ai_addrlen;
    printf("4 %d\n", rc);
    freeaddrinfo(r);
  }

  /* a symbolic service goes through /etc/services */
  rc = getaddrinfo("127.0.0.1", "http", &hint, &r);
  printf("5 %d\n", rc);
  if (rc == 0) {
    struct sockaddr_in *p = (struct sockaddr_in *)r->ai_addr;
    rc = ntohs(p->sin_port);
    printf("6 %d\n", rc);
    freeaddrinfo(r);
  }

  /* NULL node: wildcard to bind, loopback to connect */
  hint.ai_flags = AI_PASSIVE;
  rc = getaddrinfo(0, "9999", &hint, &r);
  if (rc == 0) {
    struct sockaddr_in *p = (struct sockaddr_in *)r->ai_addr;
    printf("7 %s\n", inet_ntoa(p->sin_addr));
    freeaddrinfo(r);
  } else printf("7 err %d\n", rc);
  hint.ai_flags = 0;
  rc = getaddrinfo(0, "9999", &hint, &r);
  if (rc == 0) {
    struct sockaddr_in *p = (struct sockaddr_in *)r->ai_addr;
    printf("8 %s\n", inet_ntoa(p->sin_addr));
    freeaddrinfo(r);
  } else printf("8 err %d\n", rc);

  /* a NAME -- no resolver, so this must FAIL rather than invent an address.
     It is checked as "nonzero", not as EAI_NONAME, because glibc's exact code
     depends on the box's nsswitch and this file must not be a test of that. */
  rc = getaddrinfo("no-such-host.invalid", "80", &hint, &r);
  printf("9 %d\n", rc != 0);

  /* AI_NUMERICSERV forbids the /etc/services lookup */
  hint.ai_flags = AI_NUMERICSERV;
  rc = getaddrinfo("127.0.0.1", "http", &hint, &r);
  printf("10 %d\n", rc != 0);
  hint.ai_flags = 0;

  /* ---- getnameinfo ---- */
  memset(&sa, 0, sizeof(sa));
  sa.sin_family = AF_INET;
  sa.sin_port = htons(22);
  sa.sin_addr.s_addr = htonl(0x0A0B0C0DUL);

  rc = getnameinfo((struct sockaddr *)&sa, sizeof(sa), h, sizeof(h),
                   sv, sizeof(sv), NI_NUMERICHOST | NI_NUMERICSERV);
  printf("11 %d %s %s\n", rc, h, sv);

  /* NI_NAMEREQD: a name is required and none can be had -- see the header */
  rc = getnameinfo((struct sockaddr *)&sa, sizeof(sa), h, sizeof(h), 0, 0,
                   NI_NAMEREQD);
  printf("12 %d\n", rc != 0);

  /* a named service, from /etc/services */
  rc = getnameinfo((struct sockaddr *)&sa, sizeof(sa), 0, 0, sv, sizeof(sv),
                   NI_NUMERICHOST);
  printf("13 %d %s\n", rc, sv);

  /* the host buffer is too small: EAI_OVERFLOW, not a truncated address --
     a truncated dotted quad is a DIFFERENT, valid-looking address. */
  rc = getnameinfo((struct sockaddr *)&sa, sizeof(sa), h, 4, 0, 0,
                   NI_NUMERICHOST);
  printf("14 %d\n", rc != 0);

  /* an address family this socket layer cannot connect is EAI_FAMILY, not a
     sockaddr nothing can use. */
  sa.sin_family = AF_INET6;
  rc = getnameinfo((struct sockaddr *)&sa, sizeof(sa), h, sizeof(h), 0, 0,
                   NI_NUMERICHOST);
  printf("15 %d\n", rc != 0);
  return 0;
}
