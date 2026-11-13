---
track: A
tags: [C, busybox, gibux]
prio: 70
type: bug
blocked-by: []
summary: "`static const unsigned char t[9] = { [sizeof(char)] = 1, [sizeof(short)] = 2 };` read all 0. The flat-init pre-scan understood only `[3]` and `[NAME]` designators and bailed out on any other index expression. The path it fell back to kept none of the values."
status: done
owner: claude
---

# A designator index expression drops every value of a sized array

Found by the busybox differential on 2026-11-13, while enabling DESKTOP so
that Gibux gets the POSIX `od`. coreutils/od_bloaty.c's integral_type_size
is indexed by `[sizeof(T)]`. Under pxx the table was all zero, and `od -to2`
said "2-byte integral type is not supported".

CBraceFlatIntInitCountAt now folds any other depth-1 `[expr]` with the real
constant folder (CBraceDesignatorExprIdx: rewind, fold, restore). It accepts
the index only if it is a constant ending exactly at the `]`. A range or a
non-constant name keeps the old refusal.

Test: test/c_designator_index_expression.c, checked against gcc. It covers
global, static-local and auto arrays, an unsized array, and a positional
element after a designator. The base compiler zeroed all four global
tables. The block-scope arrays were already right.
