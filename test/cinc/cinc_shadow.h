/* glibc's forwarding-header shape, exactly: /usr/include/sys/signal.h is one
   line, `#include <signal.h>`, and there is no other signal.h in that
   directory. If an ANGLED include searches the including file's own directory
   (C 6.10.2 says it must not), this file resolves to ITSELF and the
   preprocessor recurses until it runs out of include buffers -- reporting
   "nesting too deep" at whatever the cap happens to be, which is why raising
   the cap moved the error from level 17 to level 129 and fixed nothing.
   bug-c-the-preprocessor-runs-away-on-sys-param-h-resolved-from-the-host-fallback */
#include <cinc_shadow.h>
