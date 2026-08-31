---
title: Linking a pxx object into another program
order: 94
---

# Linking a pxx object into another program

`--emit-obj` (or an output path ending in `.o`) writes a relocatable ELF object
instead of a linked executable, so pxx-compiled code can be linked into a build
driven by someone else's toolchain.

```
pascal26 --emit-obj mylib.pas mylib.o
gcc -no-pie main.c mylib.o -o prog
```

Targets: **x86-64**, **i386**, **riscv32** and **xtensa**. `arm32` and
`aarch64` have no object writer. This page describes the x86-64 and i386
objects, which behave identically — same export surface, same `-no-pie`
contract, and `gcc -m32 -no-pie` for i386. The two ESP targets are a different
kind of object: they export `app_main` for an IDF image and are covered under
[Targets](../targets/).

## What the object exports

**The routines declared with the C convention, and nothing else.** In Pascal
that is `cdecl`; in C source it is every function of the translation unit.

```pascal
function pxx_sum(n: Integer): Integer; cdecl;
var i, s: Integer;
begin
  s := 0;
  for i := 1 to n do s := s + i;
  pxx_sum := s;
end;
```

Everything else the compilation defines — your other routines and the whole RTL
it pulled in — is written as a **local** symbol: a debugger can see it, the
linker cannot, so an object can never collide with its host program over a name
like `WriteLn`. Calls out to `external` routines become ordinary undefined
symbols under their link names, which the linker resolves as it would for any
other object.

If nothing carries the C convention the object would define no linkable symbol,
and pxx refuses to write it rather than hand you a file whose failure surfaces
later at your link step.

## Two things to know before you link

**`-no-pie` is required.** The backend reaches globals through absolute address
operands, so the object carries `R_X86_64_64`/`R_X86_64_32S` relocations (or
`R_386_32` on i386). A linker can satisfy those only in a non-PIE link, and today's
toolchains default to PIE, so a plain `gcc main.c mylib.o` fails with
*relocation R_X86_64_32S against `.bss` can not be used when making a PIE
object*. Add `-no-pie`.

**No initialisation runs.** Linking an object into a foreign program does not
run the Pascal main body, unit initialisation, or anything else the program
would have done on startup — the host program's `main` is the entry point, and
it never calls yours. An exported routine must therefore not depend on a global
having been assigned at startup; give it what it needs through its parameters,
or export an explicit `cdecl` init routine for the host to call first.

## What works today

Measured, not inferred: a `gcc`-built `main` linking a pxx object and calling
into it — Pascal and C sources, integer and floating-point signatures, string
work through the pxx heap, and pxx calling back out to a shared library
(`sqrt` from `libm`) resolved by the system linker.

Not yet: `--shared` for compiled sources (it serves the `.asm` frontend only), a
Pascal `library` unit, and object output for arm32 and aarch64.

One known defect, worth knowing before you link an i386 object: a pxx routine
clobbers `EBX` on i386 and does not restore it, so a C caller keeping a live
value there can crash *after* your function has returned the right answer.
x86-64 is unaffected.
