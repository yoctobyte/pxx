/* SPDX-License-Identifier: Zlib */
/* The socket veneer is implemented in src/netinet/in.c, not here; this file
   exists only so `#include <sys/socket.h>` alone still reaches it.

   WHY IT CANNOT LIVE HERE. crtl auto-pulls src/<x>.c when <x.h> COMPLETES.
   For <sys/socket.h> that is too early: <netinet/in.h> includes us, so at our
   completion in_addr_t and struct sockaddr_in do not exist yet — and
   <netinet/in.h>'s guard is already set, so the impl cannot pull them back.
   The impl therefore lives where <netinet/in.h> pulls it, once those types
   exist.

   WHY THE #ifndef. A no-op (guard-suppressed) include still triggers the
   sibling-impl pull, so an unconditional `#include <netinet/in.h>` here would
   pull src/netinet/in.c while <netinet/in.h>'s own body was still unfinished —
   in_addr_t undefined, exactly the failure this file works around. Testing the
   guard distinguishes the two orders:

     <sys/socket.h> first  — guard unset: include it for real, and its
                             completion pulls the impl.
     <netinet/in.h> first  — guard set (it is mid-flight, we were included BY
                             it): do nothing; it pulls the impl itself when it
                             completes.

   Without this file, `#include <sys/socket.h>` + socket() silently acquired a
   glibc DT_NEEDED for a function crtl implements
   (bug-cfront-spurious-dt-needed-libc-with-no-imports). */
#ifndef PXX_CRTL_NETINET_IN_H
#include <netinet/in.h>
#endif

/* CMSG_NXTHDR(3) -- glibc's algorithm, deliberately, not a stricter one.

   WHAT IT CHECKS IS THE CURRENT MESSAGE, NOT THE NEXT ONE. The buffer must
   hold this message's header, its padding and its payload, AND a full header
   after it. The next message's own cmsg_len is NOT validated here: it becomes
   the current one on the following call, and that call checks it. Reading it
   early would mean trusting a length this function has not yet vetted, which
   is the thing the ordering exists to avoid.

   The obvious-looking stricter version -- also require the next message's
   PAYLOAD to fit -- was written first and diffed against glibc: it returns
   NULL where glibc returns the header, on a truncated buffer. Divergence in
   the direction of caution is still divergence, and this is a walker over
   kernel-supplied bytes where every other program on the system uses glibc's
   answer. Matching means there is one behaviour to reason about.

   No pointer arithmetic on cmsg_len before the checks: the subtraction is
   done on the two ends of the BUFFER, whose relationship is known, and
   cmsg_len only ever appears as a size on the right of a comparison. */
struct cmsghdr *__cmsg_nxthdr(struct msghdr *mhdr, struct cmsghdr *cmsg)
{
  unsigned char *base = (unsigned char *)mhdr->msg_control;
  unsigned char *here = (unsigned char *)cmsg;
  size_t needed;
  size_t avail;

  if (cmsg == 0) return CMSG_FIRSTHDR(mhdr);
  if (cmsg->cmsg_len < sizeof(struct cmsghdr)) return (struct cmsghdr *)0;

  needed = sizeof(struct cmsghdr) + __CMSG_PADDING(cmsg->cmsg_len);
  avail  = (size_t)(base + mhdr->msg_controllen - here);
  if (avail < needed) return (struct cmsghdr *)0;
  if (avail - needed < cmsg->cmsg_len) return (struct cmsghdr *)0;

  return (struct cmsghdr *)(here + CMSG_ALIGN(cmsg->cmsg_len));
}
