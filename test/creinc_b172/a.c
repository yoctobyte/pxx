#include "hdr.h"
/* forward call to b172_set BEFORE its definition, inside an #included .c
   (CHeaderMode) — the shape that made zlib's gz_error a dynamic import. */
int b172_go(int *p){ b172_set(p, 42); return *p; }
void b172_set(int *p, int v){ *p = v; }
