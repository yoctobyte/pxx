/* sizeof of ADJACENT string literals is the size of the one array they
   concatenate to. pxx counted only the first piece, so busybox od's
   `char address_fmt[sizeof("%0n"OFF_FMT"xc")]` was 4 bytes, not 7: the
   format lost its tail and every address printed as `0`. Built by pxx and
   by gcc; the outputs must match.
   bug-c-sizeof-of-adjacent-string-literals-counts-only-the-first */
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#define OFF_FMT "l"
struct globals { int x; char address_fmt[sizeof("%0n"OFF_FMT"xc")]; int y; };
static char top[sizeof("ab" "cd" "\n")];
int main(void)
{
    struct globals G;
    strcpy(G.address_fmt, "%0n"OFF_FMT"xc");
    G.address_fmt[2] = '7';
    G.address_fmt[sizeof(G.address_fmt) - 3] = 'o';
    G.address_fmt[sizeof(G.address_fmt) - 2] = ' ';
    printf("%d %d %d %d\n", (int)sizeof G.address_fmt, (int)sizeof top,
           (int)sizeof("a" "b"), (int)sizeof(L"ab" "c"));
    printf(G.address_fmt, 11L);
    printf("|\n");
    return 0;
}
