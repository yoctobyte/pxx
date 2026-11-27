/* An empty header is a header: #include, __has_include and -include all find
   it. FreeBSD's LinuxKPI ships its placeholder headers as 0-byte files.
   bug-cpp-an-empty-include-file-is-reported-not-found */
#include "c_include_an_empty_header.h"
#include <stdio.h>
#if !__has_include("c_include_an_empty_header.h")
#error "__has_include missed the empty header"
#endif
int main(void) { printf("empty header ok\n"); return 0; }
