---
track: C
tags: [cfront, emit-obj, weak, rump, netbsd]
prio: 45
type: bug
blocked-by: []
summary: "`extern int *const __stop_x[] __attribute__((__weak__));` -- at file scope or inside a function -- came out of an object as a STRONG undefined symbol (gcc: WEAK UND), so a link where nothing defines it failed; a weak data DEFINITION was GLOBAL. Weak was honoured for functions only. Found by frank-user in rump-pxx g21."
status: done
owner: pxx2
---

# Weak data symbols were strong

New SymObjDataWeak, set from CDeclSawWeak at both global declaration paths
(block-scope externs are hoisted onto them). The four --emit-obj writers bind a
data import through ObjDataImpBind ($20 when weak), and a weak definition
exports as $21.

Test: test/c_weak_data_a.c (readelf binding, and a non-PIE gcc link printing
`1 1 4`). Remaining gaps -- GOT reference for PIE, local binding of a weak
definition, program mode -- are bug-c-weak-data-references-bind-locally-and-skip-the-got.
