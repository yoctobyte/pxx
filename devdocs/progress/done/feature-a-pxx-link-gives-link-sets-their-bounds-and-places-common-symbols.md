---
slug: feature-a-pxx-link-gives-link-sets-their-bounds-and-places-common-symbols
track: A
prio: 50
type: feature
status: done
owner: "claude-pxx"
created: 2026-11-21
found-by: an all-pxx rumpnic (Rainyday 0050 item 2), tried in scratch
tags: [link, elf, rump, rainyday]
blocked-by: []
summary: "DONE 2026-11-21. pxx --link refused two things every NetBSD rump link needs. (1) A data section named like a C identifier (link_set_domains, from __attribute__((section))): now laid out per name, contiguous, after .data, with __start_<name>/__stop_<name> defined and the whole set kept by GC when either is referenced, as ld does. (2) SHN_COMMON (-fcommon): now merged by name, largest size and alignment, displaced by a real definition, else given a .bss slot. Both against gcc+ld. Next wall for an all-pxx rumpnic: ELF TLS (feature-a-pxx-link-has-no-elf-tls)."
---

# pxx --link: link sets get their bounds, commons get placed

## How it was found

Rainyday asked whether rumpnic and librumpuser could be built by pxx; today
both are gcc. In scratch:

- the 17 rump archives were rebuilt from pxx objects (`mkarch.py`, 471 objects);
- librumpuser's 12 files and rumpnic.c, vfiodev.c and confine.c all compile
  with pxx `--emit-obj --threadsafe`.

The link through `pxx --link` (which takes pxx objects only, so the archives'
members were passed in directly) then stopped at three walls in turn.

## 1. Link sets

`allocated section 'link_set_domains' is not one pxx emits`. pxx WRITES
these sections (feature-c-section-attribute-on-x86-64-objects); its own
linker refused them. That ticket's "Not done" said so.

- **Classify.** A section whose name is a C identifier is data: writable
  PROGBITS, or read-only for a const set.
- **Lay out.** Each set's inputs go together in link order, after the rest of
  `.data`, starting at the set's largest member alignment. Nothing else sits
  between `__start_` and `__stop_`.
- **GC.** A reference to `__start_X` or `__stop_X` keeps every section of set
  X. Nothing names the entries; the walk between the two symbols is their
  only use. ld does the same.
- **Symbols.** ElfLnkDefineLinkerSyms defines `__start_X` and `__stop_X` when
  something references them.

## 2. Common symbols

`symbol 'rumpns_altq_input' is defined against special section index 65522`.
The rump replay passes `-fcommon`, and pxx emits SHN_COMMON for it. The
linker's comment said the writer never does; that was stale.

- A common is neither a strong nor a weak definition. Its size and alignment
  (st_value) merge by the largest.
- A real definition anywhere displaces it.
- Otherwise ElfLnkPlaceCommons gives it its own `.bss` slot after every
  object's sections. This runs once, before the first GC mark, so GC can
  reach the slot.

## Tests (test-core, next to the link-set rows)

- `c_lset26_pl`: the existing link-set fixture (three entries in two objects),
  main compiled by pxx too and linked by `pxx --link`. Same output as the gcc
  link.
- `c_lcom26`: `test/c_link_common_symbols.c` in three objects. A name common in
  two objects is one variable; a larger size in the second wins; a real
  definition displaces the commons; an unshared common is zero. The expected
  output is gcc+ld's.
- The refusals that should stay still do: `.multiboot` (hosted) and a bare
  `.rodata` (check_link_freestanding.sh, elf_reader_vs_readelf.sh) are not
  C identifiers.

## 3. What stops the all-pxx rumpnic now

`.tdata.curlwp_storage`: rump's `curlwp` is `__thread`, reached through
R_X86_64_GOTTPOFF. That is feature-a-pxx-link-has-no-elf-tls, and it is a
design question, not a missing case.
