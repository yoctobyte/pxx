---
slug: bug-c-the-signed-keyword-spelling-dunder-signed-is-not-recognised
track: C
prio: 45
type: bug
status: backlog
created: 2026-11-16
found-by: pixx-cc, building disk tools for pixx at 2491105c8d (repros: /data/projects/pixx/work/tooltest/repro/) B2
tags: [cfront]
blocked-by: []
summary: "`__signed__` (gcc's alternate spelling of `signed`) is not a type keyword. e2fsprogs ext2_types.h. Repro signed_kw.c."
---

## Fixed 2026-11-19 (pxx2)

The C lexer renames `__signed__` and `__signed` to `signed` after
preprocessing, before keyword classification. gcc does not define them as
macros, so `#ifdef __signed__` stays false, as in gcc. The ticket repro returns
0. test/c_dunder_signed.c (rows c_dsigned26 and c_dsigned26_i386) matches gcc:
typedefs of each width, bare `__signed__`/`__signed`, a cast, and the #ifdef.
