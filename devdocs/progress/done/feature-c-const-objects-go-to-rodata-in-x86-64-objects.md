---
slug: feature-c-const-objects-go-to-rodata-in-x86-64-objects
title: "A baked C const object is .rodata.<name> in an x86-64 object, as gcc places it"
track: C
type: feature
prio: 40
status: done
owner: claude-dupwt
found: 2026-11-19
found-by: rump meta ticket (s01 open item), split with rd
---

# A baked C const object is `.rodata.<name>` in an x86-64 object

## Before

Rainyday's repro `s01_section_attribute_ignored.c` (NetBSD link sets):

| | gcc | pxx (default `--emit-obj`) | pxx `--function-sections` |
| --- | --- | --- | --- |
| `static const struct ls lsv = {3}` | `.rodata`, A, 4 B | `.bss.lsv`, 28 B, set by the init thunk | `.data.lsv`, WA |
| `p1 = &lsv` in `link_set_foo` | WA + `.relalink_set_foo` | WA, **no relocation**: stored by the init thunk | WA + relocation |

Without `--function-sections`/`--c-static-data`, C file-scope initialisers run
as code in `__pxx_init_thunk` from `.init_array`, so every link-set entry is
NULL until constructors run (fine for rump, whose `rump_init` runs after
them; not for anything walking link sets earlier). With static data on (the
default for `--emit-obj --function-sections`), the bytes are baked, but every
const object was still writable `.data`.

## Change

- `CTryBakeGlobalInit` is now a wrapper that records, in `SymCInitByCode`,
  every global with an initialiser store it turned away (that store runs as
  code at start-up, so the global must stay writable).
- The x86-64 data-cut planner marks a cut read-only (`ODCRo`) for a C object
  the parser marked const (`SymCConstObj`), in `.data`, under
  `CStaticDataMode`, not TLS, with no user section and no store run as code.
  `ObjNumberDataCuts` keeps the mark only when the cut carries no
  relocation: a const object holding an address stays writable, as gcc's
  `.data.rel.ro` does (a relocation in a read-only section is a text
  relocation under PIE).
- A read-only cut is named `.rodata.<name>` (`.rela.rodata.<name>` +5 in
  `.shstrtab`) with flags SHF_ALLOC only, and its tail is split into a pad
  cut, as a named section's is, so trailing bytes with no symbol of their own
  never become read-only with it.

## Measured

s01 now: `.rodata.lsv` (A, 4 bytes) and `link_set_foo` WA with
`.relalink_set_foo`, matching gcc.

`test/c_obj_const_rodata.c` linked into a gcc `main`: prints `735 736 0`,
identical to the gcc-built object. `.rodata.{a,ga,arr,s,al,third,big}` are A;
`.data.{tab,pp}` (addresses) and `.data.counter` (mutated) stay WA; the
`aligned(32)` const keeps its alignment. The previous compiler emits zero
`.rodata.*` cuts for the same file. Gate quick and `test-emit-obj` pass.

## Not done

- An anonymous-struct const (`static const struct { ... } st = ...`) is not
  marked `SymCConstObj` by the parser and stays in `.data`; conservative.
- Objects built without static data (no `--function-sections`, no
  `--c-static-data`) still initialise C globals in the init thunk; their
  consts cannot be read-only by construction.
