---
track: C
tags: [c, object, link, dce, rump, netbsd]
prio: 10
type: bug
blocked-by: []
summary: "An x86-64 object relocated the call slot of every external the parse reached, including ones only an unused header `static inline` called, so the link required functions gcc's object never names. rump's librump wanted 18 that no rump library defines. Now only a slot that a surviving call or a C initialiser uses is relocated."
status: done
owner: claude-dupwt
---

# Objects require externals that only dead code called

The x86-64 object writer gives every external a slot in .data, and writes one
R_X86_64_64 per slot against the external's UND symbol (`.rela.data`). It wrote
that relocation for **every** external, including ones whose only callers were
header `static inline` bodies that DCE dropped, or that were never emitted.
gcc emits neither the body nor the reference.

Found linking buildrump's `tests/init` against a librump.a rebuilt from 229
pxx objects. The link failed with 428 undefined references to 18 functions
(`pmap_pv_remove`, `vm_map_lock`, `sowakeup`, `if_get_byindex`, ...). They sat
in the slot tables of nearly every object, and rump defines none of them in
this configuration.

## Fix

`writeELFRelX64General` marks an external live when a surviving `DynCall` site
names it, or when a baked C initialiser does. Only live slots get their
relocation. A dead slot stays zero, and its UND symbol is left unreferenced,
which no linker resolves, so symbol numbering is unchanged.

## Proof

`test/c_dead_extern_not_required.c`: a `static inline` nobody calls calls
`never_defined`, which nothing defines. The object has zero relocations naming
it and links with a gcc main. Before the fix (latest-7deee32b0f), it had one
relocation, and the link failed with an undefined reference. Rows:
c_deadext26_rel, c_deadext26. rump: librump (229/229 pxx) links.
