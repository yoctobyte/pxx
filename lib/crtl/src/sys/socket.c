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
