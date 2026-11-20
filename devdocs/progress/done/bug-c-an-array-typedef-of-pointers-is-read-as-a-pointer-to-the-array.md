---
slug: bug-c-an-array-typedef-of-pointers-is-read-as-a-pointer-to-the-array
track: C
prio: 60
type: bug
status: done
owner: pxx2
created: 2026-11-20
closed: 2026-11-20
found-by: pxx2, every Xt program (xclock, xcalc, xeyes, xload, xedit) crashed in XtDirectConvert
tags: [cfront, typedef]
summary: "`typedef P T[16]` (P a pointer typedef) and `typedef struct R *T[16]` were one pointer. ParseCTypedef skipped the dims for a pointer element, and the global and local paths read `base = pointer` as a pointer to an array typedef. The dims are now recorded, and the declaration paths count the stars actually written (CTypeSpelledStars). test/c_array_typedef_of_pointers.c (c_tdptrarr26). A pointer to such a typedef (`T *pt`) is still wrong: bug-c-a-pointer-to-an-array-typedef-of-pointers-has-no-shape."
---

# An array typedef of pointers was read as one pointer

libXt's Convert.c: `typedef CachePtr CacheHashTable[256]; static CacheHashTable
cacheHashTable;`. `cacheHashTable[i]` scaled i by 72 (the CacheRec size) and
read off the table: SIGSEGV in XtDirectConvert in every Athena app. It was
found with gdb on the crash address (`imul $0x48`).

Changed (cparser.inc):
- ParseCTypedef's scalar arm reads the dims for a pointer element too.
- Both struct arms do the same for `typedef struct T *Name[N]`.
- ParseCDeclType counts the written stars in CTypeSpelledStars.
- The global path tests the written stars (gSpelled) instead of
  `baseTk = tyPointer`, and so does the local path (lclNoStar).

Globals, locals, struct fields and parameters all match gcc on x86-64 and i386.
