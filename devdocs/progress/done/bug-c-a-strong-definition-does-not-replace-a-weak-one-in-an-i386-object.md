---
slug: bug-c-a-strong-definition-does-not-replace-a-weak-one-in-an-i386-object
track: C
prio: 35
type: bug
status: done
created: 2026-11-19
found-by: claude-dupwt, while linking i386 objects for feature-c-i386-link-for-c-objects
tags: [cfront, emit-obj, link, weak, i386]
blocked-by: []
owner: claude-dupwt
summary: "DATA half only (the function half is done: bug-c-a-call-to-a-weak-function-in-an-i386-object-binds-locally). In an i386 object a weak data definition's initialiser is a start-up store through the symbol, so another object's strong definition is overwritten: c_weak_data_a.o + _b.o print `1 1 4`, gcc `1 1 40`. The x86-64 fix (4251456a9a, bake the value into .data) cannot simply be widened: the i386 writer does not handle a C global placed in .data by CPlaceGlobalInData. Measured: it wrote wv as a .bss symbol with the raw tagged offset 0x200006c8, and the program segfaulted."
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


## 2026-11-19 (claude-dupwt): the function half is fixed, the data half measured

The function half landed separately
(bug-c-a-call-to-a-weak-function-in-an-i386-object-binds-locally).

For data, widening the x86-64 gates (both CPlaceGlobalInData sites in
cparser.inc, plus CTryBakeGlobalInit) to TARGET_I386 gave `1 1 40` for a+b,
but a.o ALONE segfaulted. writeELFRel386General writes every data symbol
as `Syms[i].Offset` in shndx 5 (.bss), and an offset CPlaceGlobalInData
moved is tagged (SymOffIsData, 0x20000000), so `wv` became a .bss symbol at
0x200006c8. The i386 writer needs the x86-64 writer's data-part handling
(SymOffIsData -> shndx 3, SymOffDataPart value) for its local, export and
GlobFix paths before the gates can be widened. It also has no CDataReloc
(baked address) output, so an address-valued weak initialiser must stay a
store until it does. Reverted, not committed.

## Data half fixed (same day)

The i386 writer now writes a .data-placed variable correctly: SymOffIsData
gives shndx 3 (.data) with SymOffDataPart as the value, in both the local and
the exported data loops. Its GlobFix patch loop already handled such offsets.
With that, the x86-64 gates widen to i386 for a weak data definition in an
object: both CPlaceGlobalInData sites in cparser.inc, and the extra conjunct
that limited them to x86-64 or ESP. CTryBakeGlobalInit bakes only plain
values outside x86-64, since this writer has no baked-address relocations,
so an address-valued weak initialiser stays a start-up store.

| link (tools/pxx_link_i386.sh) | before | after | gcc |
| --- | --- | --- | --- |
| c_weak_data_a.o + _b.o | 1 1 4 | 1 1 40 | 1 1 40 |
| c_weak_data_a.o alone | 1 1 4 | 1 1 4 | 1 1 4 |

Also checked: `int *wp __attribute__((weak)) = &x;` (store path) reads 5,
and a weak `int wa[3] = {7,8,9}` (baked) sums to 24. Rows i386/c_wkd386 and
i386/c_wkd386_a.
