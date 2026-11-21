---
slug: bug-c-a-wide-string-literal-truncates-hex-escapes-above-ff
track: C
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-11-21
found-by: claude-pxx (writing test/c_crtl_utf8_locale.c)
tags: [cfront, literals, wchar, silent]
blocked-by: []
summary: "A \\x escape above 0xFF in a wide string literal is truncated and the elements after it are wrong: L\"\\x79C1\\x306F\" \"a\" gives 6f 61 0 under pxx, 79c1 306f 61 under gcc; L\"\\x79C1\\x306Fa\" gives 7a 0 <garbage> where gcc gives 79c1 306fa. Silent wrong values, no diagnostic."
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
