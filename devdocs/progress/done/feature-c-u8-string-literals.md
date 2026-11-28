---
slug: feature-c-u8-string-literals
track: C
prio: 60
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (Panorama all-pxx program: libxkbcommon 1.13.1 through compdb.py replay)
tags: [clexer]
summary: "`u8'...'` (C11) and `u8'c'` (C23) were lexed as the identifier u8 followed by a literal. They are ordinary narrow literals of UTF-8 bytes, which is what pxx's strings already hold, so the lexer now consumes the prefix. `\u200E` inside comes out as e2 80 8e, as with gcc. u''/U'' (char16_t/char32_t) are left unrecognised rather than read narrow. libxkbcommon's scanner.c. Test: c_xkbpp26."
---

# C u8 string literals

Concatenation (`u8"ab" "cd"`) works because both pieces are narrow.
