---
title: Dive
order: 5
---

# Dive

Everything on this page is true today, on this checkout. No slides, no
roadmap talk — read this once and you'll know what PXX actually is, fast.
Full documentation is linked at the bottom if you want more.

## What is it

**PXX** (dialect name **pascal26**) is a Pascal compiler that writes its own
Linux ELF executables directly — no external assembler, no external linker,
no libc in the default path. One person, one from-scratch codebase: lexer,
parser, IR, six CPU backends, its own runtime library, its own GTK-based
widget set. Nothing borrowed from FPC, Borland, or anyone else — but it
speaks FPC's Object Pascal dialect, so existing Pascal knowledge carries over.

## See it work

```pascal
program hello;
begin
  writeln('Hello, world!');
end.
```

```sh
./pxx hello.pas hello
./hello
```

```
Hello, world!
```

That compile produced a real static ELF binary, in one step, with no `as`,
`ld`, or `gcc` anywhere in the process.

## Why it's worth a second look

- **Self-hosting, provably.** The compiler is written in its own dialect and
  compiles itself to a byte-identical fixed point — build 2 must equal
  build 3, exactly, on every target that self-hosts. That's the development
  gate, not a claim; it fails the build if it's not true.
- **Small by choice, not by accident.** Default managed-string build: ~31 KB
  hello-world. Switch to the frozen-string ABI (`-uPXX_MANAGED_STRING`) and
  the same program is a 287-byte static ELF. Verified on this checkout.
- **Six targets, one compiler.** x86-64, i386, aarch64, arm32 all self-host
  byte-identical; xtensa and riscv32 target bare-metal ESP32. `--target=`
  picks the backend, nothing else changes.
- **More than Pascal.** The same backend also compiles a C frontend
  (real-world C — SQLite, Lua fixtures pass), a Python-like dialect
  (Nil Python, `.npy`), and its own assembly-source frontend.

<details markdown="1">
<summary><strong>How does it actually turn source into a binary?</strong></summary>

One pass, no external tools:

1. **Lexer** — source text to tokens. Dispatches by file extension: `.pas`
   Pascal, `.c` C, `.npy` Nil Python, `.bas` early BASIC.
2. **Parser** — tokens to an AST. Frontends share expression-parsing and
   type-checking where their semantics overlap.
3. **IR** — AST lowers to a linear intermediate representation, target-agnostic.
4. **Codegen** — IR lowers to target machine bytes. Six backends, one IR.
5. **ELF writer** — the compiler's own linker. Static binary by default; adds
   `PT_DYNAMIC`/`DT_NEEDED`/GOT/PLT automatically if you import a C library.

No optimization passes exist yet — no constant folding, no register
allocation, no dead-code elimination. What you write is what gets emitted.

See [Architecture](../reference/architecture.md) for the full picture.
</details>

<details markdown="1">
<summary><strong>What's actually solid vs. still rough?</strong></summary>

Solid: the core Pascal language — classes, interfaces, generics, exceptions,
managed strings, dynamic arrays — compiles on all four Linux self-host
targets (verified: a class-based program builds clean on x86-64, i386,
aarch64, and arm32 alike), plus the C and Nil Python frontends against
real-world C headers/libraries, and DWARF debug info on all four Linux
targets.

Rough, honestly: the two ESP32 targets (xtensa, riscv32) don't support
classes yet, and are emit-only — not self-host targets; there's no built-in
optimizer at all (no constant folding, no register allocation); integer
arithmetic wraps without overflow checks; `private`/`protected` are parsed
but not access-enforced; Nil Python is capped at 4 parameters and has no
pointer syntax of its own. Full list: [Limits](../reference/limits.md).

This is early, experimental software — not something to point at
security-sensitive, safety-sensitive, financial, legal, or medical work.
</details>

<details markdown="1">
<summary><strong>Can I actually use this?</strong></summary>

Read it, build it, run it locally, study it — yes. Right now the repository
grants **no open-source or other license**: default copyright applies, and
public visibility on GitHub is not itself permission to copy, modify,
redistribute, or rely on the code. This may change later. See
[`LICENSE.md`](https://github.com/yoctobyte/pxx/blob/master/LICENSE.md) in
the repository for the exact, current terms.
</details>

## Go deeper

- [Install](../install/) and [Getting started](../getting-started/) — set up
  the pinned compiler and compile your own first program.
- [Language reference](../language/) — the full Pascal dialect.
- [Standard library](../library/) — the RTL and PCL units.
- [Targets](../targets/) — cross-compilation, ESP32, the C and Nil Python
  frontends in depth.
- [Reference](../reference/) — command line, architecture, limits, glossary.
