---
track: C
tags: [c, initialisers, data, rump, netbsd]
prio: 10
type: bug
blocked-by: []
summary: "`static const struct { int n; int v[]; } I = { 2, { 7, 8 } };` read back I.v as garbage: the walker gave the flexible array member length 0 and skipped every element as excess, and the object had only sizeof bytes. NetBSD ioconf.c's cfiattrdata locator tables read NULL names, and the pxx-built rumpnic crashed in strlen from config_add_attrib_dict. A static object's FAM is now walked unbounded, measured at the declaration, and the object grown to hold it."
status: done
owner: claude-dupwt
---

# An initialised flexible array member is dropped

C99 forbids initialising a flexible array member. gcc (and NetBSD's
generated `ioconf.c`) do it for static objects: the elements live past
`sizeof`, and the symbol's size covers them.

    static const struct cfiattrdata pcicf_iattrdata = {
        "pci", 2, { { "dev", "-1", -1 }, { "function", "-1", -1 }, } };

pxx's aggregate walker had `UFldArrLen = 0` for `ci_locdesc[]`, so
`CInitWalkArray` got `count = 0` and skipped every element. The global was
`sizeof` bytes, and reading `ci_locdesc[j]` read the neighbours. In the rump
kernel, `config_add_attrib_dict` passed a NULL locator name to
`prop_dictionary_set_string_nocopy`, and strlen faulted at the first
`config_found` (pci at mainbus).

## Fix

- `CInitWalkMember`: while `CInitFamOpen`, a one-dimensional array field of
  length 0 is walked with no bound. `CInitFamMax` records the byte offset its
  last element reaches.
- At a non-array struct global's declaration, a record ending in a FAM
  (`CRecEndsInFam`) gets a dry walk (`emit = False`) to measure it.
  `CGrowGlobalBytes` repoints the symbol at a slot of that size, while nothing
  has read its offset yet. It goes back into `.data` if static-data mode had
  already placed it there.
- The deferred replay (`CEmitDeferredCAggInits`) opens the FAM the same way.

Local aggregates are left closed: gcc refuses a non-static FAM initialiser.

## Proof

`test/c_flexible_array_member_init.c`: int, pointer and struct FAMs, a
non-const one followed by another global, and the ioconf shape. Output is
identical to gcc's, hosted and as a `--freestanding --system-libs` object
(rows c_faminit26, c_faminit26_f).
