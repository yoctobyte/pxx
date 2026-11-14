---
slug: bug-c-main-initialisers-inflate-main-frame
track: C
prio: 60
type: bug
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "File-scope initialisers were compiled INTO main, so every temporary became one of main's locals: a trivial main had a 5,520-byte frame, toybox's over 24 KB, and toybox's recursion guard (distance from main's &argc > 24000) made every command answer 'Unknown command'. They now run in `__pxx_c_main_init`, a static proc main calls."
---

# C: main's frame carried every global initialiser's temporaries

`CEmitMainInitProc` (cparser.inc) emits `__pxx_c_main_init` before main's body
address is taken; main calls it where the inline code used to be. Same shape as
the unit-init proc ParseCUnit already makes for a C unit. Verified on x86-64,
i386, aarch64, arm32; self-host fixedpoint unchanged in shape.
