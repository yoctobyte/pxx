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
gcc main.c mylib.o -o prog
```

Targets: **x86-64**, **i386**, **riscv32** and **xtensa**. `arm32` and
`aarch64` have no object writer. This page describes the x86-64 and i386
objects. They share an export surface, but **not** a relocation model: an
x86-64 object is position-independent and links either way, an i386 object is
position-dependent and needs `gcc -m32 -no-pie`. The two ESP targets are a
different kind of object: they export `app_main` for an IDF image and are
covered under [Targets](../targets/).

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

**x86-64 needs no link flags; i386 needs `-no-pie`.** On x86-64 the backend
reaches globals through `[rip+disp32]`, so `.text` carries only
`R_X86_64_PC32`. A plain `gcc main.c mylib.o` is enough, and the object links
into a PIE and a non-PIE, under `gcc` and under `clang`. The `R_X86_64_64`
relocations that remain are all in `.data` — absolute pointers *stored* in
data, which a PIE resolves at load time like any other shared object.

The i386 backend still reaches globals through absolute operands, so an i386
object carries `R_386_32` in `.text`. GNU `ld` will accept those in a PIE, but
only by making the text segment writable at load time:

```
warning: relocation in read-only section `.text'
warning: creating DT_TEXTREL in a PIE
```

That is why `-no-pie` remains the documented form for i386. It is not merely
cosmetic — a hardened link refuses it outright, while the same flag on an
x86-64 object links clean:

```
$ gcc -m32 -Wl,-z,text main.c mylib32.o     # read-only segment has dynamic
                                            # relocations -> error
$ gcc      -Wl,-z,text main.c mylib.o       # links
```

> Before 2026-09-01 x86-64 behaved like i386 and this page said `-no-pie` was
> required on both. Objects emitted by an older pxx still need it.

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

Also a **shared library** — see below. Not yet: a Pascal `library` unit, and
object output for arm32 and aarch64.

## A shared library

`--shared` (or an output path ending in `.so`) writes an `ET_DYN` shared
library. x86-64 only.

```
pascal26 --shared mylib.pas mylib.so
gcc main.c ./mylib.so -o prog      # link against it
# ...or load it at run time with dlopen/dlsym
```

The export surface is the same as an object's — the C-convention routines, and
nothing else — so the `cdecl` example above applies unchanged. A library that
exports nothing is refused rather than written.

What works inside one: the pxx heap, managed strings, dynamic arrays, classes
with virtual methods, and calls out to `external` routines, which are resolved
through the library's own GOT with a `DT_NEEDED` on the providing library.

**No initialisation runs here either.** Loading the library does not run the
Pascal main body, so an exported routine must not depend on a global having
been assigned at startup — the same rule as for objects, and for the same
reason.

Before 2026-09-01 `--shared` served the `.asm` frontend only. A compiled source
produced a valid `ET_DYN` that exported nothing, because the writer built its
export list from the assembly frontend's label table. It was blocked on the
backend rather than the writer: a shared library is relocated at load by
definition, so the absolute address operands that `-no-pie` rescued in an
object could not work here at all.

## One known defect

Worth knowing before you link an i386 object: a pxx routine clobbers `EBX` on
i386 and does not restore it, so a C caller keeping a live value there can
crash *after* your function has returned the right answer. x86-64 is
unaffected.
