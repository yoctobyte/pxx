---
track: C
tags: [cfront, sizeof, string-literals, pathb, fontconfig]
prio: 80
type: bug
blocked-by: []
summary: "`sizeof(\"charset\")` was 4. The literal arm of ParseCSizeof sized it right (8) but left the token unconsumed, and the re-parse fallback fires when sz still equals the pointer-size default -- which an 8-byte literal does. Every 7-character literal answered 4. fontconfig's gperf name pool came out 28 bytes short and \"charset\", \"foundry\", ... stopped being built-in objects."
status: done
owner: pxx2
---

# sizeof of a parenthesised 7-character literal was 4

cparser.inc ParseCSizeof: the literal arm consumes the literal when `)`
follows it; anything else after it (`"abc"[0]`) goes back to the default so
the expression re-parse sizes it.

Still open, deliberately: `sizeof(("abcdefg"))` (a second pair of parens)
reaches the expression path, which sizes an AN_STR_LIT node as 4. That node
kind is also the result of a folded `__builtin_strchr` (a pointer), so it
cannot simply answer length + 1.

Test: test/c_sizeof_literal_8_bytes.c (row c_szlit826) against gcc, x86-64
and i386.
