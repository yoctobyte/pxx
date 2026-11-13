---
track: B
tags: [C, cfront, elf, gibux]
prio: 40
type: bug
blocked-by: []
summary: "`extern struct proc procs[128];` in a header gave every object that included it a private, never-addressed .bss slot of the array's full size (the parser allocates storage before it knows the declaration stays extern-only). Gibux's kernel carried 5.5 MB of such slots across ten objects. The x86-64 object writer now punches them out at write time (ObjBssPlanImportDrops in elfwriter.inc). The kernel image's .bss went from 0x5564a8 to 0x381c10. Gibux item 6."
status: done
owner: unassigned
---

# An extern array reserves .bss in every declaring object

## Cause

The C frontend allocates storage for a file-scope array as it parses the
declaration. When the declaration stays `extern`, the object writer names
the import's UND symbol for every reference (ObjDataSymIndexForOff). So the
slot is never addressed, just carried, at the array's full size.

## Fix (compiler/elfwriter.inc, x86-64 relocatable writer)

ObjBssPlanImportDrops runs after CRegisterCDataImports. Each import slot at
least one section-alignment unit long becomes a hole, rounded down to the
alignment so everything above it stays aligned. Stored offsets stay in
original coordinates. ObjBssRemap converts them where an offset leaves the
compiler:

- the GlobFix section relocations;
- a .bss symbol's st_value (ObjDataValue);
- the .bss fallback of a C data relocation (ObjCDataRelaSym);
- the .bss section size.

**Safe by refusal:** the whole plan is abandoned, and the object is written
as before, if anything section-relative lands inside a hole. That covers a
GlobFix, a defined symbol, or a CDR_SYM target. ObjBssRemap raises an
internal error rather than return an address inside a hole.

## Verified

- test/c_extern_array_reserves_no_bss_{use,def}.c with
  tools/check_extern_bss.sh. Two imports (256 KB and 64,000 B) sit between
  real statics, with .data pointers into both an import and a moved slot.
  - The declaring object's .bss is 0x12cd8, down from 0x626d8 with the
    d9a0d9a599-era compiler. The control fails as expected.
  - The output matches gcc, both pxx-linked and gcc-linked.
- Gibux kernel objects: an old/new pairing of every relocation and .bss
  symbol shows a monotone drop, so nothing kept original coordinates. The
  pxx-linked and the gcc-linked images both boot hello and test-sh.

## What it exposed

With the dead slots gone, the Gibux test-sh failed at 12 of 71 .bss
layouts. Gibux's kfree re-read `h->cls` after `b->next` had overwritten it
(the two structs alias). That is a wild write per free in a pxx kernel. gcc
-O2 hid it under strict aliasing; the slots used to absorb the writes. It
was fixed in Gibux 23c88eb.
