---
title: Glossary
order: 93
---

# Glossary

## Compiler and build terms

| Term | Meaning |
| --- | --- |
| PXX | The project name for the compiler and language toolchain. |
| `pascal26` | The current compiler executable name under `compiler/`. |
| `pxx` | The wrapper created by `install.sh`; it calls the pinned compiler with library roots. |
| Pinned compiler | The stable compiler selected by `stable_linux_amd64/default/pinned`. |
| Self-hosting | The compiler is written in its own Pascal dialect and can compile itself. |
| Fixedpoint | The compiler compiles itself, that result compiles it again, and the two binaries are byte-identical — **at the default optimisation level**. Expanded under [Build terms a newcomer meets first](#build-terms-a-newcomer-meets-first). |
| Direct ELF | PXX writes ELF output itself instead of invoking an external assembler or linker. |
| RTL | Runtime library units under `lib/rtl`. |
| PCL | Component/UI library units under `lib/pcl`. |

## Language terms

| Term | Meaning |
| --- | --- |
| Managed string | Reference-counted string storage with automatic retain/release. |
| Dynamic array | Heap-backed array sized with `SetLength` and queried with `Length`. |
| RTTI | Runtime type information, used by reflection and component streaming work. |
| Unit | Reusable Pascal module imported with `uses`. |
| `-Fu` | Command-line option adding a Pascal unit search root. |
| `-I` | Command-line option adding a C include path and Pascal unit search root. |
| `PXX` symbol | Conditional-compilation symbol defined by PXX for Pascal input. |
| `FPC` symbol | Conditional-compilation symbol reserved for real Free Pascal builds. |

## Cross-language vocabulary

PXX accepts Pascal, C and Nil Python, so its documentation mixes three
vocabularies. Most terms have a counterpart in the language you already know,
and the mapping is usually more useful than a definition.

### Python / Nil Python → Pascal

| Python / Nil Python | Pascal | note |
| --- | --- | --- |
| module | unit | one file, one namespace |
| `import` | `uses` | but see [name resolution](../language/name-resolution.md) |
| `self` | `Self` | the instance the method was called on |
| `cls` | `Self` in a `class function` | short for *class* — the class, not an instance. The abbreviation exists only because `class` is a reserved word and cannot be a parameter name. |
| dunder | constructor / operator overload | "dunder" = **d**ouble **under**score, as in `__init__`, `__eq__` |
| `__init__` | constructor | |
| `__name__` (on a class) | `ClassName` | |
| `__str__` / `__repr__` | — | no single Pascal counterpart: `str()` is for a reader, `repr()` for a programmer, and they differ for exceptions and containers |
| decorator (`@property`) | — | a function wrapping a declaration; PXX accepts a fixed set, not arbitrary ones |
| list / dict / set | dynamic array / — / — | |
| `None` | `nil` | |
| duck typing | — | binding by whether the member exists rather than by declared type |

### Pascal → Python / Nil Python

| Pascal | Python / Nil Python | note |
| --- | --- | --- |
| unit | module | |
| `uses` | `import` | |
| interface / implementation section | — | Python has no declaration/definition split |
| RTL | the standard library | PXX's own, under `lib/rtl` |
| managed string | `str` | reference-counted, freed automatically |
| `nil` | `None` | |
| overload | — | Python resolves one name to one function; Pascal picks by argument types |

## Build terms a newcomer meets first

Plain-language versions of three terms defined tersely above; the definitions
agree, and this is the one to read first if either is new.

| Term | Meaning |
| --- | --- |
| Pinned compiler | The blessed stable binary everything else builds with. Libraries and examples are compiled with it rather than with a freshly built compiler, so a broken build in one lane cannot poison another. |
| Fixedpoint | The compiler compiles itself and the result is byte-identical to the binary that produced it — at the default optimisation level. It is the property that proves a compiler can still reproduce itself. |
| Frontend | The part that parses one language. PXX has several (Pascal, C, Nil Python) and they share everything below the parser. |
| Shim | A unit PXX wrote itself that presents a familiar API under the name `mimic_<module>`, standing in for a package rather than pretending to be it. |

## Target terms

| Term | Meaning |
| --- | --- |
| Host target | The CPU architecture where the compiler binary runs. |
| Output target | The CPU architecture selected with `--target=` for emitted code. |
| Cross-compilation | Building output for an architecture different from the host. |
| QEMU user-mode | Emulator used to run Linux cross-target binaries during tests. |
| ESP profile | Embedded platform profile selected by `--esp-profile=bare`. |
| Object output | Relocatable `.o` output selected by `--emit-obj` or a `.o` output name. |

## Terms in the release notes and the ESP pages

| Term | Meaning |
| --- | --- |
| Nil Python | The Python-shaped language PXX compiles ahead of time into a native program, with no interpreter. It is not CPython. `pxx` is the command; Nil Python is one of the languages it compiles. See [Nil Python](../targets/nil-python.md). |
| Pin, "pin v450" | A numbered compiler build that the project has frozen and named. The docs say which pin a figure was measured with. [Reporting bugs](./reporting-bugs.md#what-to-put-in-a-report) shows how to find out which one you have. |
| Hosted | Running as a Linux program, natively or under QEMU user mode, as opposed to on an ESP chip. "Hosted Xtensa" and "hosted riscv32" are Linux builds for the ESP chips' CPUs that the project's tests use to check ESP code under QEMU. See [Targets](../targets/index.md). |
| Unity build | Several C source files compiled as one translation unit, from one file that `#include`s the others. See [A project with several files](../getting-started/c.md#a-project-with-several-files). |
| Soft-float | Floating point done by integer routines instead of FPU instructions. ESP builds use it, and link the routines in only when a program uses a float. See [ESP32: Floating point](../targets/esp32.md#floating-point). |
| Windowed, call0 | The two Xtensa calling conventions (`--xtensa-abi=`). An ESP-IDF build for a named Xtensa chip, such as `--target=esp32s3`, is windowed, because ESP-IDF requires it; plain `--target=xtensa` and `--esp-profile=bare` use call0. See [Command line](./cli.md#options). |
| ESP-IDF mode, bare profile | The two ways to build for an ESP chip. ESP-IDF mode, the default, emits an object that ESP-IDF links into firmware and runs on real boards. The bare profile (`--esp-profile=bare`) emits a standalone image that runs under QEMU only. See [ESP32: Mode 2](../targets/esp32.md#mode-2-esp-idf-component-emit-obj). |
| `--platform=esp` | Selects the ESP platform layer, where FreeRTOS provides tasks rather than processes. An ESP chip name in `--target=` implies it. See [Command line](./cli.md#options). |

## Eliah IDE terms

`apps/ide/` names its components with a Hebrew scheme; see
[Examples → The Eliah IDE](../examples/index.md#the-eliah-ide) for the full table.

| Term | Meaning |
| --- | --- |
| `garin` | Render-agnostic IDE core (editor buffer, project model, form document, builder). |
| `eliah` | GTK face of the IDE. |
| `ilja` | ANSI/TUI face of the IDE. |
| `bochan` | Headless test driver that exercises `garin` with no GUI/TUI face linked. |
| `eduth` | Assertion/verdict library `bochan` reports results to. |

## Next

- [Command line](./cli.md)
- [Current limits](./limits.md)
- [Targets](../targets/index.md)
