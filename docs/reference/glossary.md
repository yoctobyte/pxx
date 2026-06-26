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

## Target terms

| Term | Meaning |
| --- | --- |
| Host target | The CPU architecture where the compiler binary runs. |
| Output target | The CPU architecture selected with `--target=` for emitted code. |
| Cross-compilation | Building output for an architecture different from the host. |
| QEMU user-mode | Emulator used to run Linux cross-target binaries during tests. |
| ESP profile | Embedded platform profile selected by `--esp-profile=bare`. |
| Object output | Relocatable `.o` output selected by `--emit-obj` or a `.o` output name. |

## Next

- [Command line](./cli.md)
- [Current limits](./limits.md)
- [Targets](../targets/)
