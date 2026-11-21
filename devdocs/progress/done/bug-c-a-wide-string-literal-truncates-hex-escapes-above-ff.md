---
slug: bug-c-a-wide-string-literal-truncates-hex-escapes-above-ff
track: C
prio: 45
type: bug
status: done
owner: ""
created: 2026-11-21
found-by: claude-pxx (writing test/c_crtl_utf8_locale.c)
tags: [cfront, literals, wchar, silent]
blocked-by: []
summary: "DONE 2026-11-21: escapes in wide literals keep their wchar_t value, \\u/\\U are universal character names (narrow and wide), L'...' reads raw UTF-8; test c_wlit26. A \\x escape above 0xFF in a wide string literal is truncated and the elements after it are wrong: L\"\\x79C1\\x306F\" \"a\" gives 6f 61 0 under pxx, 79c1 306f 61 under gcc; L\"\\x79C1\\x306Fa\" gives 7a 0 <garbage> where gcc gives 79c1 306fa. Silent wrong values, no diagnostic."
---

# A wide string literal truncates `\x` escapes above 0xFF

## Measured (2026-11-21)

```c
const wchar_t *a = L"\x79C1\x306F" "a";
const wchar_t *b = L"\x79C1\x306Fa";
printf("%x %x %x %x | %x %x %x\n", a[0], a[1], a[2], a[3], b[0], b[1], b[2]);
```

| | output |
|---|---|
| gcc | `79c1 306f 61 0 \| 79c1 306fa 0` |
| pxx | `6f 61 0 0 \| 7a 0 85a6a550` |

So `a` loses its first element and keeps only the low byte of the second.
`b` comes out as `0x7a` and then a NUL where gcc has two elements. The
third element of `b` is read past the end of the literal.

In C, a hex escape takes every hex digit that follows, and in a wide literal
its value is limited by `wchar_t` (32 bits here), not by `char`. It looks as
though the escape is converted at narrow-literal width and the result is
then widened byte by byte. That is a guess: the lexer has not been read yet.

## Test that would close it

The program above, against gcc, plus `\u`/`\U` and octal escapes in `L""`,
`u""` and `U""` literals, and concatenation of a wide literal with a narrow
one.

test/c_crtl_utf8_locale.c works around this with an explicit array; switch
it back to the literal once this is fixed.

## Done, 2026-11-21

**Cause.** A wide literal is lexed as UTF-8 bytes and decoded to wchar_t
elements at parse time (CWideDecodeNext). The lexer appended every `\x` and
octal escape as ONE BYTE (`Chr(n and 255)`), whatever the literal's width.
`\x79C1` became the byte 0xC1, a UTF-8 lead byte, which then swallowed the
bytes after it. `\u` and `\U` were not escapes at all: the `u` was kept as a
letter. A wide character constant had the same truncation and read raw UTF-8
as its first byte, so `L'私'` did not even compile.

**Fix (clexer.inc, cparser.inc).**
- In a wide literal an escape is appended as the UTF-8 form of its full
  value (CLexAppendUtf8). That includes 5- and 6-byte forms, and a 7-byte
  `$FE` form for values past 0x7FFFFFFF; the decoder reads all of them.
- `\u` and `\U` take exactly 4 or 8 hex digits and append the code point
  as UTF-8, in narrow literals as well, as gcc does. Too few digits is
  gcc's "incomplete universal character name" error.
- `L'...'` keeps the full value of an escape and decodes raw UTF-8
  (CDecodeCharBodyW).
- Narrow literals are unchanged otherwise.

**Test.** test/c_wide_literal_escapes.c (row c_wlit26, plus i386 and
aarch64), against gcc. It covers hex, octal and UCN escapes in L"", hex
digits running on, the 32-bit maximum, raw UTF-8, wide+narrow concatenation,
static and local arrays, sizeof, wide character constants and narrow \u/\U.
It does not compile on master. test/c_crtl_utf8_locale.c is back to the
`L"\x79C1\x306F" "a"` literal.
