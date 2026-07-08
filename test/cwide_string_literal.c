/* Guard: feature-c-wide-string-literals (c-testsuite 00220 covers the UTF-8
   multibyte path with embedded 你/€/¢; this ASCII guard asserts the L"..." prefix
   lexes, builds a wchar_t[] with 4-byte codepoint elements, and NUL-terminates).
   Exits 42 on success. */
#include <wchar.h>

int main(void)
{
    wchar_t a[] = L"hi";
    if (a[0] != 0x68 || a[1] != 0x69 || a[2] != 0) return 1;   /* 'h' 'i' NUL */
    if (sizeof(a) != 3 * sizeof(wchar_t)) return 2;            /* 4-byte elems */

    wchar_t *p = a;
    int n = 0;
    while (*p) { n++; p++; }                                    /* 4-byte stride */
    if (n != 2) return 3;

    return 42;
}
