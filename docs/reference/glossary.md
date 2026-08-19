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
| Fixedpoint | A self-build reaches byte-identical output across rebuild stages. |
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

### Build terms a newcomer meets first

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

## Eliah IDE terms

`apps/ide/` names its components with a Hebrew scheme; see
[Examples → Apps](../examples/#apps) for the full table.

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
- [Targets](../targets/)
