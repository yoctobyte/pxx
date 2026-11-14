---
track: C
tags: [C, layout, alignment, gibux, freestanding]
prio: 10
type: bug
blocked-by: []
summary: "A C global whose STRUCT TYPE is over-aligned (a member with aligned(4096)) got a slot offset that was a multiple of 4096 inside a .bss whose base was only 8- or 16-aligned, so the object sat at e.g. 3368 mod 4096. Only aligned(N) written on the variable itself raised the section alignment. Now every global slot raises it (ReqBssAlign) to the slot's alignment, and moving an initialised global into .data uses the record's alignment too. Also new: _Alignof / __alignof__ (C11 / gcc), which were 'expected C expression'."
status: done
owner: unassigned
---

# A global of an over-aligned struct type is not placed on its alignment

Reported by the Gibux session on 2026-11-14 as a blocker. Gibux's NVMe driver
keeps its queues in `static struct ctrl ctrls[4]`, where `struct ctrl` has
`aligned(4096)` members. The controller rejects queues that are not
page-aligned, so NVMe worked in the gcc kernel and failed in the pxx kernel.
AHCI (1024- and 256-aligned members) and virtio worked only by luck.

The layout was right: offsets 4096/8192/12288 and size 77824 match gcc. The
cause was where the section starts:

- AllocVar and AllocArray align a global's slot to the record's alignment
  (UClsAlign), so the offset inside .bss was a multiple of 4096.
- The writers raise the .bss base, or the object's .bss sh_addralign, only to
  ReqBssAlign.
- ReqBssAlign was set only from an `aligned(N)` written on the declaration
  itself (bug-c-aligned-on-a-global-variable-is-ignored).

So the base stayed 8- or 16-aligned, and every such global sat at the same
wrong remainder (3368 mod 4096 in the repro).

## Fix (compiler/symtab.inc)

- Both global-slot paths (AllocVar, AllocArray) raise ReqBssAlign to the
  slot's final alignment.
- CPlaceGlobalInData, which moves an initialised global into .data, also
  takes the record's alignment, of the variable itself or of its array
  elements. An executable keeps a >16-aligned initialised global in .bss, as
  before; an object raises .data's sh_addralign.

## Also: `_Alignof`

`_Alignof(type)`, and gcc's `__alignof__` / `__alignof` with a type or an
expression, now fold to a constant, in expressions and in constant
expressions such as array dimensions (CParseAlignof, cparser.inc). They were
refused with "expected C expression".

## Tests (test-core, after the atomics rows)

- `cgovalign26`, `cgovalign_a64`: `test/c_global_overaligned_struct.c`,
  output equal to gcc's. It covers:
  - 4096-aligned structs in a static array, alone, initialised;
  - 1024/256-aligned members (AHCI's shape), in .bss and .data;
  - offsets and size;
  - `_Alignof` / `__alignof__`, including one in an array dimension.
- `c_fs_ovalign`: the same shapes in a `--freestanding --emit-obj` object
  linked by gcc give `mods 0`. The frozen compiler gives `mods 6192`.

pxx's own `--link` already honoured the input sections' alignment when
laying out .data and .bss. Its output section headers still record
sh_addralign 16, which affects nothing at load time.
