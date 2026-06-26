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
subprocess in the normal path.

## Next

- [Pascal basics](../language/pascal-basics.md)
- [Command-line reference](../reference/cli.md)
