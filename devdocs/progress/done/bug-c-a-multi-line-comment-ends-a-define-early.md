---
slug: bug-c-a-multi-line-comment-ends-a-define-early
track: C
prio: 70
type: bug
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (Panorama all-pxx program: libxkbcommon 1.13.1 through compdb.py replay)
tags: [cpreproc]
summary: "A block comment spanning lines inside a #define, with no backslashes on its lines, ended the directive at the comment's first newline. The rest of the body became top-level text ('stray token at top level'). In C a comment is one space (phase 3), and a directive ends at the next newline after it. libxkbcommon's keymap.h xkb_keys_foreach is written this way. CPReadLine now continues a DIRECTIVE line across a newline inside a comment. Ordinary lines still end there, which keeps their line numbers. Test: c_xkbpp26 (FOREACH, TWO, __LINE__ after them)."
---

# C a multi line comment ends a define early

CPLineIsDirective(line) decides it. The line counter advances the same way as for the in-comment backslash splice. 123 of 265 xkbcommon units failed on this one header.
