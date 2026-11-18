---
track: C
tags: [c, attributes, object, link-set, rump, netbsd]
prio: 10
type: feature
blocked-by: []
summary: "__attribute__((section(\"name\"))) on a C global now gives it an ELF section of that name in an x86-64 --emit-obj object. Before, it worked only on ESP and was silently ignored on x86-64 (rump gap S1). NetBSD link sets work across pxx objects and mixed with gcc ones: each entry is exactly its own bytes at its natural alignment, so __stop_ - __start_ counts right."
status: done
owner: claude-dupwt
---

# section("name") on x86-64 objects

rump's silent gap S1 (Rainyday docs/rump-pxx/README.md). NetBSD's
`__link_set_add_*` puts one pointer per entry in `link_set_<set>`, and the
consumer walks `__start_link_set_<set>` .. `__stop_link_set_<set>`, which the
linker makes. gcc's rump objects carry `link_set_domains`,
`link_set_prop_linkpools` and `link_set_evcnts`. pxx honoured the attribute
only in ESP objects (feature-c-section-attribute-on-esp). On x86-64 the
global went to `.data`/`.bss`, the set was empty, and nothing said so.

## How

The general x86-64 writer already cuts `.data`/`.bss` into one section per
global (`.data.<name>`, the data cuts). A named global's cut now takes the
user's name (`ODCFull`), and its relocations go in `.rela<name>`. An object
with one turns function sections on, as a weak definition does.

Getting a link set right took three more things:

1. **Exact size.** A cut normally runs to the next global and keeps the
   alignment padding. In a link set that padding is a hole, which `__stop_ -
   __start_` counts as an entry. The gap after a named cut now becomes a cut
   of its own (`.data.pxx.padN`).
2. **Natural alignment.** pxx places 16-byte-or-larger globals at 16, and
   the cut inherited it. ld pads every input section to its alignment, so an
   8-byte entry at 16 left a hole. A named cut gets the largest power of two
   dividing its size, at most 8, as gcc does.
3. **PROGBITS.** In a hosted object without static data, an initialised
   global lives in `.bss` and is set by the init thunk. ld puts a NOBITS
   input in an output section apart from the PROGBITS one of the same name,
   so a set mixing gcc and pxx objects lost the pxx entries. A named global
   is now always placed in `.data`; its initialiser may still be a
   start-up store.

If the data cuts must be dropped (a self-relative word spanning two globals),
an object holding a named global is refused by name rather than writing a
plain `.data`.

## Proof

`test/c_attribute_section_link_set.c`: three entries in two objects, plus
unrelated globals before and after them. It is counted and walked under a gcc
main for pxx+pxx hosted, pxx+pxx `--freestanding`, and gcc+pxx, and matches
gcc each time. The `-O2` build was checked by hand.

Not done: a pxx-linked executable (`--link`) does not synthesise
`__start_`/`__stop_`.
