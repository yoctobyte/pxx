/* Include-search-path regression, three rows and they are one question asked
   three ways:
     cinc_local.h   QUOTED -> the including file's own directory (baseDir)
     cinc_msg.h     QUOTED -> falls through baseDir to a -I project root
     cinc_shadow.h  QUOTED here, but it is a FORWARDER whose own body says
                    `#include <cinc_shadow.h>` -- and the ANGLED form must NOT
                    look in the including file's directory, or it finds itself.
   The third row is glibc's sys/signal.h shape and it ran away until the search
   learned the split. */
#include "cinc_local.h"
#include "cinc_msg.h"
#include "cinc_shadow.h"
int main(void) {
    printf(CINC_LOCAL);
    printf(CINC_MSG);
    printf(CINC_SHADOW);
    return 0;
}
