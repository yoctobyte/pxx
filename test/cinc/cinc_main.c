/* Include-search-path regression: cinc_local.h resolves via the including
   file's own directory (baseDir); cinc_msg.h resolves via a -I project root. */
#include "cinc_local.h"
#include "cinc_msg.h"
int main(void) {
    printf(CINC_LOCAL);
    printf(CINC_MSG);
    return 0;
}
