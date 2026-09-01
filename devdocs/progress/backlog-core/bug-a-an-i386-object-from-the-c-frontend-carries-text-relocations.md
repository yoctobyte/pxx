---
slug: bug-a-an-i386-object-from-the-c-frontend-carries-text-relocations
track: A+C
prio: 40
type: bug
status: new
blocked-by: []
owner: ""
created: 2026-09-01
found-by: frankA (while adding .init_array to the i386 object writer; pre-existing, not caused by it)
summary: "An i386 --emit-obj object from the C frontend carries absolute relocations against .text, so linking it produces `relocation in read-only section .text` and `creating DT_TEXTREL in a PIE`. Measured with `gcc -m32 host.c lib.o`: 2 warnings, identical before and after the .init_array work, so it is pre-existing and independent of it. The program RUNS -- ld resolves it by making .text writable -- but a DT_TEXTREL binary is refused by hardened toolchains (`-Wl,-z,text`) and defeats page sharing. The x86-64 writer does not have this: its equivalent sites were converted to PC-relative, and the emit-obj relocation rows assert .text carries no absolute relocation. i386 has no such row, which is why nobody noticed."
---

# An i386 object from the C frontend carries text relocations

Found while making i386 objects run their initialisers
(`bug-a-an-i386-emit-obj-object-still-never-runs-its-initialisers`). **Not caused
by that work** — measured on an object built before it and one built after, and
both produce the same two warnings:

```
ld.bfd: cl386.o: warning: relocation in read-only section `.text'
ld.bfd: warning: creating DT_TEXTREL in a PIE
```

## Why it matters despite the program running

`ld` resolves this by marking `.text` writable at load. So the object links, the
program runs, every existing row stays green — which is exactly why it survived.
What it costs is real: `-Wl,-z,text` refuses the link outright, hardened
distributions build with it, and a writable `.text` cannot be shared between
processes.

## The x86-64 side already solved this and the difference is instructive

`test-emit-obj`'s x86-64 rows assert that `.text` carries **no** absolute
relocation, and that assertion exists because `IR_PROCADDR` was emitting
`mov rax, imm64` — an `R_X86_64_64` against `.text` — until the `@proc` case was
added to `test/test_emit_obj.pas` specifically to give the census a population
that could contain it. The comment there says so.

**i386 has no equivalent row.** So the same class of defect is unmeasured on a
target that has an object writer, which makes this a test gap first and a codegen
bug second. Adding the assertion is the cheap half and should probably come
first; it will name the sites.

## Suggested shape

1. Add the missing relocation-class row to the i386 half of `test-emit-obj`,
   mirroring the x86-64 one (`! readelf -rW ... | grep -q 'R_386_32 .*\.text'`
   modulo the intended `.rel.init_array` entry, which IS an absolute relocation
   against `.text` and is correct — it lives in `.init_array`, not in `.text`,
   so scope the assertion to relocations whose SECTION is `.text`).
2. Convert the offending sites to PC-relative or GOT-indirect, as the x86-64
   path was.

Note for whoever takes it: the `.rel.init_array` entry added on 2026-09-01 is an
`R_386_32` against the `.text` symbol and is NOT an instance of this bug — it
patches a slot in `.init_array`. An assertion written as "no R_386_32 mentioning
.text anywhere" would flag it and be wrong.
