/* -nostdinc / --freestanding: a hand-written prototype of a libc-named
   function must not make pxx synthesise `#include <netinet/in.h>` from its
   crtl name map. Under -nostdinc that include was "not found"; with kernel
   -I roots it pulled in the kernel's own header. The object leaves htonl
   undefined for the link, as gcc does (NetBSD's rump tree, Gibux g03). */
unsigned int htonl(unsigned int);
unsigned int f(unsigned int x) { return htonl(x); }
