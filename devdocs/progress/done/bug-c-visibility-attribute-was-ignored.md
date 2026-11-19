---
slug: bug-c-visibility-attribute-was-ignored
track: C
prio: 40
type: bug
status: done
created: 2026-11-19
found-by: rump repro s09 (Rainyday docs/rump-pxx), re-run by rd
tags: [cfront, emit-obj, attributes, rump, rainyday]
blocked-by: []
summary: "__attribute__((visibility(\"hidden\"))) was skipped: the object's symbol stayed DEFAULT where gcc writes HIDDEN (rump repro s09). The lexer now carries the visibility on the next token (CAttrFlags bits 12..13, as ELF st_other), CDeclVisibility reads it for a function (prototype or definition: ProcCVis) and a global (SymCVis), and the x86-64 object writer puts it in st_other for exported functions and data. hidden, protected and internal; matches gcc on test/c_visibility_attribute.c."
---

## Measured

`readelf -s` on test/c_visibility_attribute.c, gcc and pxx --emit-obj, both:
`hid=HIDDEN hvar=HIDDEN plain=DEFAULT prot=PROTECTED proto_hid=HIDDEN pvar=DEFAULT`.
The pxx object links with gcc (test/c_visibility_attribute_main.c, `6 6`).
Rows: c_visibility_attribute, c_visibility_attribute_link.

## Not done

- Only the x86-64 object writer writes st_other; the ELF32 and aarch64/
  arm32 object writers still write 0.
- `#pragma GCC visibility push(hidden)` and `-fvisibility=hidden` are not
  read. Nothing measured needs them yet.
- An undefined symbol declared hidden is written DEFAULT (gcc marks it).
