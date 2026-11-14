/* busybox's bzip2.c / decompress_unxz.c shape: static prototypes in a header,
   the definitions in a .c file the main file #includes. The included .c is
   part of THIS translation unit, so the definition is the prototype's.
   pxx attributed it to a module of its own and the object called an
   undefined `sph_times6`. bug-c-a-static-defined-in-an-included-c-file-is-never-emitted */
#include <stdio.h>
#include "c_static_proto_in_header.h"
#include "c_static_proto_in_header_impl.c"
int main(void) { printf("%d\n", sph_times6(7)); return 0; }
