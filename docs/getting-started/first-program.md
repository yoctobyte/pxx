---
title: First program
order: 21
---

# First program

Create `hello.pas`:

```pascal
program hello;
begin
  writeln('Hello, world!');
end.
```

Compile it:

```sh
./pxx hello.pas hello
```

Run the executable:

```sh
./hello
```

The first compiler argument is the source file. The optional second argument is
the output path. If you omit the output path, PXX derives one from the source
name and refuses to overwrite the source file.

PXX emits a final ELF executable directly. There is no assembler or linker
subprocess in the normal path. That's the default, but not the only output
PXX can produce. `--emit-obj` writes a relocatable `.o` instead, and `--shared`
(or an output name ending in `.so`) writes a shared library on x86-64. Both
export only the routines marked for C linkage, such as Pascal `cdecl`, so for
this program they refuse, because it defines nothing another program could
link against. See the [command-line reference](../reference/cli.md).

## Next

- [Pascal basics](../language/pascal-basics.md)
- [Command-line reference](../reference/cli.md)
