---
slug: bug-c-attribute-weak-was-ignored
track: C
prio: 70
type: bug
status: done
created: 2026-11-15
found-by: pxx (Gibux seat), rump-pxx S5
tags: [cfront, emit-obj, attributes, silent]
blocked-by: []
summary: "`__attribute__((weak))` was dropped: a weak definition was `T` (gcc `W`), and a weak extern a required import (gcc `w`), so `maybe ? maybe() : 0` could not link without `maybe`. The lexer flags it on the next token (CAttrAlignValues bit 16); a prototype becomes ProcWeakExternal (the optional import Pascal's weakexternal already is), a definition ProcCWeakDef, bound STB_WEAK by ObjProcBind. An x86-64 object holding a weak definition is written with function sections: in one .text the call was already a resolved rel32 to the object's own copy, so another object's strong definition could not win (gcc 20, pxx 2). Functions only; weak DATA is still ignored. Tests: c_weak (executable), c_weak_nm (W wk, W wk2, w maybe), c_weak_g and c_weak_l (a strong definition in a second object wins, gcc and pxx --link)."
---
