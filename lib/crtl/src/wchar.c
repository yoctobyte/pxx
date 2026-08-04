/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <wchar.h>.
 *
 * wchar_t is 32-bit here (see the header), so wcslen is a plain scan for the
 * terminating zero — no encoding is involved and it is exact.
 *
 * towlower/towupper are ASCII-only, which is not a simplification: crtl is
 * C-locale-only, and glibc's C locale does exactly this. Verified against a gcc
 * build over the whole range -1..255 plus U+0100, U+0391, U+4E00 and U+1F600 —
 * every value above 127 is returned unchanged, and WEOF (-1) passes through.
 *
 * These were declared in <wchar.h> and <wctype.h> but implemented nowhere, so
 * a program calling one imported it from glibc and stopped being statically
 * linked — the same declared-but-unreachable shape as
 * bug-cfront-spurious-dt-needed-libc-with-no-imports, which is how it was
 * found (test/cwide_string_literal imported wcslen).
 */

#include <wchar.h>

size_t wcslen(const wchar_t *s)
{
    const wchar_t *p = s;
    while (*p) p++;
    return (size_t)(p - s);
}

wint_t towlower(wint_t c)
{
    if (c >= 'A' && c <= 'Z')
        return c + ('a' - 'A');
    return c;
}

wint_t towupper(wint_t c)
{
    if (c >= 'a' && c <= 'z')
        return c - ('a' - 'A');
    return c;
}
