/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_NETDB_H
#define PXX_CRTL_NETDB_H 1

#include <sys/_types.h>   /* __socklen_t -- the leaf header, see the note below */

struct sockaddr;          /* declared here so the prototypes below need no include */

/* EVERY DECLARATION IN THIS FILE SITS ABOVE THE TWO INCLUDES AT THE BOTTOM,
   AND THAT ORDER IS LOAD-BEARING -- the note down there has the mechanism and
   the two measured symptoms. In one line: crtl pulls src/<x>.c when <x.h>
   completes, a guard-suppressed include counts as completion, and both
   src/netdb.c and src/netinet/in.c are therefore spliced in at the point those
   includes are reached. Anything below them does not exist for either.

   Neither symptom was a compile error. `err == HOST_NOT_FOUND' became an
   undeclared identifier treated as 0, so hstrerror answered "Unknown resolver
   error" for every code except 0; and an incomplete `struct addrinfo' made
   getaddrinfo write its fields at the wrong offsets. Plausible wrong values,
   with a warning at most. src/sys/socket.c documents the third instance. */
/* h_errno IS NOT errno. The resolver reports through its own variable, with
   its own small set of codes, and a caller that reads errno after a failed
   gethostbyname gets whatever the last syscall left there -- which is where
   "Success" as a lookup failure message comes from. It is a real variable
   here, not a macro over errno, so that hstrerror(h_errno) means what it says.
   Not thread-local: this runtime's resolver is not either, and pretending
   otherwise would be a claim rather than a guarantee. */
extern int h_errno;

#define HOST_NOT_FOUND 1
#define TRY_AGAIN      2
#define NO_RECOVERY    3
#define NO_DATA        4
#define NO_ADDRESS     NO_DATA

/* The resolver's own strerror. Static string, never NULL. */
const char *hstrerror(int err);
void herror(const char *s);

/* /etc/services lookups. `proto' may be NULL, meaning "any protocol", and the
   port in a servent is in NETWORK byte order -- that is the field's contract
   and the classic place an htons() gets applied twice. */
struct servent {
  char  *s_name;
  char **s_aliases;
  int    s_port;      /* network byte order */
  char  *s_proto;
};

struct servent *getservbyname(const char *name, const char *proto);
struct servent *getservbyport(int port, const char *proto);
void setservent(int stayopen);
void endservent(void);
struct servent *getservent(void);


/* The EAI_* codes are glibc's numbers, and the whole set is here rather than
   the four that were once used: a caller comparing against a code this header
   does not define gets an undeclared identifier TREATED AS 0, and 0 is
   success. A missing error name is therefore not a missing feature, it is a
   test that passes. */
#define EAI_BADFLAGS  -1
#define EAI_NONAME    -2
#define EAI_AGAIN     -3
#define EAI_FAIL      -4
#define EAI_FAMILY    -6
#define EAI_SOCKTYPE  -7
#define EAI_SERVICE   -8
#define EAI_MEMORY   -10
#define EAI_SYSTEM   -11
#define EAI_OVERFLOW -12

/* getnameinfo flags, glibc's values. */
#define NI_NUMERICHOST 1   /* do not attempt a reverse lookup */
#define NI_NUMERICSERV 2   /* print the port, do not name it */
#define NI_NOFQDN      4   /* the nodename portion only */
#define NI_NAMEREQD    8   /* FAIL rather than return a numeric address */
#define NI_DGRAM      16   /* name the UDP service rather than the TCP one */

#define NI_MAXHOST  1025
#define NI_MAXSERV    32

struct hostent {
  char  *h_name;
  char **h_aliases;
  int    h_addrtype;
  int    h_length;
  char **h_addr_list;
};
#define h_addr h_addr_list[0]

struct addrinfo {
  int              ai_flags;
  int              ai_family;
  int              ai_socktype;
  int              ai_protocol;
  __socklen_t      ai_addrlen;
  struct sockaddr *ai_addr;
  char            *ai_canonname;
  struct addrinfo *ai_next;
};

#define AI_PASSIVE     0x0001
#define AI_CANONNAME   0x0002
#define AI_NUMERICHOST 0x0004
#define AI_NUMERICSERV 0x0400


struct hostent *gethostbyname(const char *name);
struct hostent *gethostbyaddr(const void *addr, __socklen_t len, int type);
int  getaddrinfo(const char *node, const char *service,
                 const struct addrinfo *hints, struct addrinfo **res);
void freeaddrinfo(struct addrinfo *res);
const char *gai_strerror(int errcode);
/* getnameinfo: the reverse of getaddrinfo. THERE IS NO REVERSE RESOLVER here,
   so the host is always numeric; NI_NAMEREQD therefore FAILS with EAI_NONAME
   rather than quietly handing back a dotted quad, which is the answer busybox's
   xmalloc_sockaddr2host expects when a name cannot be had. See src/netinet/in.c. */
int getnameinfo(const struct sockaddr *sa, __socklen_t salen,
                char *host, __socklen_t hostlen,
                char *serv, __socklen_t servlen, int flags);


/* THE TWO INCLUDES BELOW GO LAST -- everything this header declares is ABOVE
   them, and that is a rule rather than tidiness.

   <sys/socket.h>'s completion splices src/sys/socket.c, which includes
   <netinet/in.h>, whose completion splices src/netinet/in.c -- and THAT is
   where getaddrinfo, freeaddrinfo, gai_strerror and getnameinfo are
   implemented. Its own `#include <netdb.h>' is a no-op, because this header's
   guard was set before the chain began, so the implementation sees exactly
   the part of this file that sits above these two lines.

   With `struct addrinfo' BELOW them the implementation compiled against an
   incomplete struct of that name and wrote its fields at the wrong offsets:
   getaddrinfo returned 0 and the caller read sin_family out of sin_addr, so
   10.1.2.3:80 came back as 2.0.0.0:0. AI_PASSIVE and AI_CANONNAME were
   undeclared identifiers treated as 0 in the same window, which quietly made
   every AI_PASSIVE bind ask for the loopback. No error either time.

   That is why `struct addrinfo' spells its length field __socklen_t, from the
   leaf <sys/_types.h>: it is the same type socklen_t is, and reaching it does
   not drag the splice in. Anything added BELOW these lines is invisible to the
   implementation. */
#include <sys/socket.h>
#include <netinet/in.h>


#endif
