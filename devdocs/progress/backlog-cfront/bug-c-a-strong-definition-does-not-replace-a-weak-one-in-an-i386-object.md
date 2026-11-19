---
slug: bug-c-a-strong-definition-does-not-replace-a-weak-one-in-an-i386-object
track: C
prio: 35
type: bug
status: backlog
created: 2026-11-19
found-by: claude-dupwt, while linking i386 objects for feature-c-i386-link-for-c-objects
tags: [cfront, emit-obj, link, weak, i386]
blocked-by: []
summary: "In an i386 object a weak definition is WEAK, but references to it inside the object do not go through the symbol, so another object's strong definition does not replace it. Weak FUNCTION: c_weak_a.o + c_weak_b.o linked with tools/pxx_link_i386.sh print `2 -1 3 1`, against `20 -1 3 1` from the x86-64 objects and gcc. The call to wk has no relocation (the i386 writer has no function sections, which is what makes such a call relocatable on x86-64). Weak DATA: c_weak_data_a.o + _b.o print `1 1 4`, against `1 1 40`. The references are R_386_PC32 against wv, but the initialiser is a start-up store, the cause fixed for x86-64 in 4251456a9a, whose .data baking is gated to x86-64."
---

# A strong definition does not replace a weak one in an i386 object

## Measured (2026-11-19, master at 4251456a9a)

| link (tools/pxx_link_i386.sh) | i386 | x86-64 objects / gcc |
| --- | --- | --- |
| c_weak_a.o c_weak_b.o | 2 -1 3 1 | 20 -1 3 1 |
| c_weak_data_a.o c_weak_data_b.o | 1 1 4 | 1 1 40 |
| c_weak_data_a.o alone | 1 1 4 | 1 1 4 |

Binding is already right: `wk`, `wk2`, `wv` are WEAK, and `maybe`, `maybe_v`
and `__stop_maybe` are WEAK UND.

## Two causes

- **Function.** The call to `wk` in main is a direct rel32 inside `.text`
  with no relocation. On x86-64 a call becomes a relocation against the
  callee's symbol only under `--function-sections` (ObjCallFixIsRelocatable),
  which the i386 writer does not implement. A narrower fix: give a call to a
  ProcCWeakDef callee an R_386_PC32 against its symbol (REL, implicit addend
  -4 in the field), function sections or not.
- **Data.** CPlaceGlobalInData / CTryBakeGlobalInit for a weak definition are
  gated to x86-64 (and ESP freestanding objects). Whether the i386 writer
  writes CDataReloc entries for a baked address must be checked before
  widening the gate.

Not a link blocker: the link succeeds and the weak copy is used. Whether
anything in toybox depends on a cross-unit override has not been checked.
