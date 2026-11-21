/* GNU's \e and \E are ESC (27), in character constants and in strings, as
   gcc and clang read them. pxx read them as the letter (101), so toybox's
   `echo -e '\e'` and `printf '\e'` printed an 'e' (bug-c-toybox-test-suite-
   failures). The other escapes are here so a decoder that drops one is seen. */
#include <stdio.h>

int main(void)
{
    const char *s = "\e[1m\E";
    printf("char  e=%d E=%d\n", '\e', '\E');
    printf("str   %d %d %d %d %d len=%d\n", s[0], s[1], s[2], s[3], s[4],
           (int)sizeof("\e[1m\E") - 1);
    printf("other %d %d %d %d %d %d %d %d\n", '\a', '\b', '\f', '\n', '\r',
           '\t', '\v', '\?');
    printf("str2  %d %d %d\n", "\a\v\?"[0], "\a\v\?"[1], "\a\v\?"[2]);
    return 0;
}
