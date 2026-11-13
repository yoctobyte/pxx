---
track: A
tags: [C, busybox, gibux]
prio: 70
type: bug
blocked-by: []
summary: "`sizeof(\"ab\" \"cd\")` was 3, gcc says 5: ParseCSizeof sized only the first of several adjacent string literals. busybox od's address format buffer came out 4 bytes instead of 7, and every address printed as `0` followed by a stray `lxc`."
status: done
owner: claude
---

# sizeof of adjacent string literals counts only the first

Found by the busybox differential on 2026-11-13, after DESKTOP was turned
on for the full POSIX `od` (Gibux). coreutils/od_bloaty.c has
`char address_fmt[sizeof("%0n"OFF_FMT"xc")]` and patches the buffer at
`sizeof - 3`/`- 2`. In the pxx build the buffer was 4 bytes, so the
patched characters landed inside the `%0n` and the format lost its tail.

ParseCSizeof's string arm took `Tokens[TokPos - 1].SLen + 1`, the size
of one token. It now adds up every consecutive string token and counts a
single NUL. If any piece is `L"..."`, the whole literal is wide: the
codepoints of every piece, plus 1, times sizeof(wchar_t).

Test: test/c_sizeof_adjacent_string_literals.c, checked against gcc. The
base compiler answered 4 3 2 12 where gcc answers 7 6 3 16.
