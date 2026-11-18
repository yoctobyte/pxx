---
track: C
tags: [cfront, builtins, rump, netbsd]
prio: 50
type: bug
blocked-by: []
summary: "gcc's builtins worked only with the right header in scope. `__builtin_memcpy` and the other library builtins became calls to undeclared memcpy & co. in a unit with no <string.h> (NetBSD sys/endian.h), and `__builtin_ffs` and the other bit builtins needed crtl's <stdlib.h> in a hosted unit (rump-pxx g10, g11). The preprocessed unit now gets the standard extern prototype for each library builtin it mentions, and, hosted, a static copy of each bit helper whose crtl declaration is absent."
status: done
owner: pxx2
---

# Builtins that needed a header

compiler/cpreproc.inc: CAddLibBuiltinDecls (both modes) and CAddHostedBuiltins
(the --freestanding copies, only for helpers whose `__pxx_builtin_X(` crtl
declaration is not in the text, since <stdlib.h>'s stdlib.c is auto-pulled and
would collide). Prototypes use `__typeof__(sizeof 0)` for size_t: the
injection runs after preprocessing, where `__SIZE_TYPE__` would not expand.

Test: test/c_builtin_no_header.c against gcc (x86-64, i386); a unit that does
include <stdlib.h> and calls __builtin_ffs still links one copy.
