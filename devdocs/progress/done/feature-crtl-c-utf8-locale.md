---
slug: feature-crtl-c-utf8-locale
track: C
prio: 30
type: feature
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [crtl, toybox]
blocked-by: []
summary: "DONE 2026-11-21: C.UTF-8 through setlocale and newlocale/uselocale (per thread), UTF-8 multibyte conversion with glibc's rules, and the class/width/case tables generated from glibc's own C.UTF-8 (tools/gen_crtl_unicode.py); not built on ESP. toybox 1594 -> 1601 of 1604. crtl supports only the C/POSIX locale, so utf8 cases in toybox's fold/fmt/echo/file tests differ from glibc's C.UTF-8. A C.UTF-8 locale (mbrtowc/wcwidth over UTF-8 when selected) would close them."
---

# crtl: C.UTF-8

setlocale(LC_ALL, "") with LANG=C.UTF-8 should select it.

## Done, 2026-11-21

Two locales exist now, C and C.UTF-8. They differ only in LC_CTYPE, as in
glibc.

**Selection.**
- `setlocale` accepts C, POSIX, and C.UTF-8 in any spelling whose codeset
  normalises to `utf8`. It returns the name as given, resolves `""` through
  LC_ALL, then LC_<category>, then LANG, and builds glibc's composite LC_ALL
  string when the categories differ. A failing LC_ALL call changes nothing.
- `newlocale` and `uselocale` give the same two locales, per thread.
  **This is the path toybox actually takes** (`main.c`:
  `uselocale(newlocale(LC_CTYPE_MASK, "C.UTF-8", 0))`). Doing setlocale
  alone moved toybox only from 1592 to 1594.
- Any other name fails with NULL, which is what glibc does for a locale that
  is not installed.

**Conversion.**
- `mbrtowc`, `wcrtomb`, `mbtowc`, `mblen`, `wctomb`, `mbstowcs` and
  `wcstombs` follow glibc's measured rules: 1 to 6 bytes (up to U+7FFFFFFF,
  not capped at U+10FFFF), overlong forms and surrogates invalid, C0/C1/FE/FF
  invalid at once, and an overlong or surrogate prefix reported as incomplete
  until the sequence is complete.
- A sequence split across `mbrtowc` calls is carried in `mbstate_t`.
- `MB_CUR_MAX` is 6 under C.UTF-8, and `nl_langinfo(CODESET)` is "UTF-8".

**Tables.**
- `wcwidth`, the twelve `isw*` classes and `towlower`/`towupper` come from
  glibc's own C.UTF-8, extracted by tools/gen_crtl_unicode.py into
  lib/crtl/src/wchar_unicode.inc (glibc 2.43): 3794 ranges plus 186/204 case
  runs, about 27 KB.
- They are not built on ESP (`__PXX_PLATFORM_ESP__`, a new predefine), and
  setlocale refuses C.UTF-8 there.
- Regenerating on another glibc moves them to that glibc's Unicode version.
  For that reason the generator's `--check` is not in the gate.

**Test.** test/c_crtl_utf8_locale.c (rows c_u8loc26_ts plus i386 and aarch64,
all `--threadsafe`, because one probe uses a second thread). It checks names,
the conversion edge cases, a hash of every table over all code points, the C
locale before and after, and that a uselocale is per thread. Expected output
is glibc's.

**Found on the way:** bug-c-a-wide-string-literal-truncates-hex-escapes-above-ff
(the test uses an explicit array instead of `L"\x79C1..."`).
