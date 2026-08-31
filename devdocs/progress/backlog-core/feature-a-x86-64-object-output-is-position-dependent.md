---
track: A
prio: 50
type: feature
status: backlog
found: 2026-08-31
found-by: frankC
owner: ""
blocked-by: []
summary: "A pxx x86-64 .o needs `-no-pie` to link, and modern toolchains default to PIE, so `gcc main.c mylib.o` fails with `relocation R_X86_64_32S against .bss can not be used when making a PIE object`. The cause is the BACKEND, not the writer: EmitDataRef emits an 8-byte absolute operand and EmitGlobRef a 4-byte sign-extended absolute displacement, so an object carries R_X86_64_64/R_X86_64_32S. The fix is a rip-relative global-reference form under --emit-obj (R_X86_64_PC32), which changes instruction ENCODINGS and therefore lengths -- deliberately not bundled into feature-a-a-general-x86-64-relocatable-object-writer, which landed the writer at 41045d7b4. Nothing is broken: -no-pie links and runs today under gcc, clang and tcc, and is documented in docs/reference/objects.md. Raise this when someone must link a pxx object into a PIE they do not control."
---

# x86-64 object output is position-dependent, so a link needs `-no-pie`

The general x86-64 object writer landed (41045d7b4). Its relocation model is
absolute, and that is a deliberate, stated choice rather than an oversight —
option (a) of the three the parent ticket set out. This is option (b).

## The symptom, exactly

```
$ pascal26 --emit-obj mylib.pas mylib.o
$ gcc main.c mylib.o -o prog
/usr/bin/ld: mylib.o: relocation R_X86_64_32S against `.bss' can not be used
             when making a PIE object; recompile with -fPIE
$ gcc -no-pie main.c mylib.o -o prog        # works
```

Measured 2026-08-31 with binutils ld, and the object links and runs correctly
under `gcc -no-pie`, `clang -no-pie` and `tcc`.

## Where it actually lives

Not in the writer. Two backend emitters decide it:

- `EmitDataRef` (`emit.inc`) — an 8-byte absolute data address, so
  `R_X86_64_64`.
- `EmitGlobRef` (`emit.inc`) — a 4-byte absolute global address. Every x86-64
  site is a `[disp32]` SIB form, which the CPU sign-extends, so `R_X86_64_32S`.

A linker can satisfy either only in a non-PIE link with everything below 2 GiB.

## The work

Teach the x86-64 backend a rip-relative global-reference form, selected under
`--emit-obj`, and emit `R_X86_64_PC32`. **The reason this is not a small
change** is that `[rip+disp32]` and `[disp32]` are different ModRM encodings of
different lengths, so switching form under a flag moves every subsequent code
offset — branch fixups, proc body addresses, DWARF ranges. It is backend work
with a real blast radius, which is why it was filed rather than bundled.

An alternative worth pricing first: keep the absolute form and emit a
`R_X86_64_64` GOT-style indirection for globals under `--emit-obj` only, the way
external calls already work (the operand names our own `.data` slot; the slot
carries the relocation). That costs a load per global reference in object output
only, and needs no encoding change at all.

## What it is NOT

Not a correctness bug — objects link and run today. Not a blocker for
`meta-a-pxx-produces-linkable-code`, whose measurement (a gcc-built caller
linking a pxx object) is satisfied by `-no-pie`.

## Umbrella

[[meta-a-pxx-produces-linkable-code]]
