---
title: "C: binary integer literals (0b101) were not lexed"
status: done
owner: claude-dupwt
prio: 65
area: cfront
---

`0b101` is a GNU C extension and standard C23. pxx's C lexer read it as `0`
followed by the identifier `b101`, so amdgpu's `case 0b001:`
(link_dp_capability.c) and `0b11` arguments (gfx_v9_4_2.c) failed to parse.
Found in the GPU-driver census (feature-nodisx-linux-gpu-drivers-built-by-pxx).

Fix: the number lexer (clexer.inc) reads 0b/0B digits, which may be unsigned
to fit, as hex and octal are. The #if evaluator (cpreproc.inc) reads them
too. Test row c_binlit26 covers code, a case label, a u suffix, a 64-bit
value, sizeof and #if.
