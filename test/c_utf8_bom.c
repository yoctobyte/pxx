/* SPDX-License-Identifier: Zlib */
/* A UTF-8 byte-order mark (EF BB BF) at the start of a source file, and at
   the start of an #included header, is skipped, as gcc and clang do. Before
   the fix pxx read it as a token: "stray token at top level: ''". */
#include <stdio.h>
#include "c_utf8_bom.h"
int main(void)
{
    printf("bom header value %d\n", BOM_HEADER_VALUE);
    return 0;
}
