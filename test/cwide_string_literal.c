/* Guard: feature-c-wide-string-literals (c-testsuite 00220 covers the UTF-8
   multibyte path with embedded 你/€/¢; this ASCII guard asserts the L"..." prefix
   lexes, builds a wchar_t[] with 4-byte codepoint elements, and NUL-terminates).
   Exits 42 on success. */
#include <wchar.h>

/* bug-c-wide-string-literal-narrow-in-value-context: L"..." used as a VALUE
   (assigned to a wchar_t*, passed as an argument, sizeof'd directly, in a
   struct initializer) was reaching codegen as raw narrow UTF-8 bytes instead
   of being widened like the array-initializer shape above — sizeof(L"abcde")
   read 6 (byte length) instead of gcc's 24, and wcslen()/pointer walks ran
   off the end. gcc oracle for every check below:
     arr: len=5 sizeof=24 c0=97 c1=98
     ptr: len=5 c0=97 c1=98
     sizeof(L"abcde") == 24
     L'x' == 120
     wcslen(argument) == 11, first two chars 'h' 'e'
     struct field: len=12, first char 's' */
struct WStrHolder { const wchar_t *p; };

int takesWide(const wchar_t *p)
{
    if (wcslen(p) != 11) return 10;
    if (p[0] != 'h' || p[1] != 'e') return 11;
    return 0;
}

int main(void)
{
    wchar_t a[] = L"hi";
    if (a[0] != 0x68 || a[1] != 0x69 || a[2] != 0) return 1;   /* 'h' 'i' NUL */
    if (sizeof(a) != 3 * sizeof(wchar_t)) return 2;            /* 4-byte elems */

    wchar_t *p = a;
    int n = 0;
    while (*p) { n++; p++; }                                    /* 4-byte stride */
    if (n != 2) return 3;

    /* the ticket's isolated arr/ptr comparison, side by side */
    wchar_t arr[] = L"abcde";
    const wchar_t *ptr = L"abcde";
    if (wcslen(arr) != 5 || sizeof(arr) != 24) return 4;
    if (arr[0] != 97 || arr[1] != 98) return 5;
    if (wcslen(ptr) != 5) return 6;                             /* was reading past the end */
    if (ptr[0] != 97 || ptr[1] != 98) return 7;                 /* was 0x64636261 packed bytes */

    if (sizeof(L"abcde") != 24) return 8;                       /* was 6 (byte length) */

    wchar_t c = L'x';
    if (c != 120) return 9;

    if (takesWide(L"hello world") != 0) return 12;

    struct WStrHolder s = { L"struct field" };
    if (wcslen(s.p) != 12 || s.p[0] != 's') return 13;

    return 42;
}
