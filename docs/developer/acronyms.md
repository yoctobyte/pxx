# Acronyms And Glossary

Short definitions for acronyms and shorthand used across this project's
documentation, source comments, commit messages, and handover notes. Where a
term has a generic meaning and a project-specific one, the project-specific
sense is noted.

## Project And Process

| Term | Expansion | Notes |
|------|-----------|-------|
| PXX | (provisional project / compiler name) | The name is still open; the built executable is `compiler/pascal26`. |
| WIP | Work In Progress | Code or docs committed or staged mid-task, not yet complete or fully verified. |
| TODO | To Do | Tracked remaining work; see [`todo.md`](todo.md). |
| FPC | Free Pascal Compiler | The reference Pascal compiler used to bootstrap and cross-check (`fpc-check`). |
| npy / NPY | (Nil Python source file) | `.npy` is the Nil Python frontend's source extension. |

## Compiler Internals

| Term | Expansion | Notes |
|------|-----------|-------|
| AST | Abstract Syntax Tree | Parser output; lowered to IR. |
| IR | Intermediate Representation | The default backend path; self-recompiles to a fixedpoint. |
| SSA | Static Single Assignment | IR-style form where each value is assigned once. |
| RTL | Run-Time Library | The Pascal support library (`lib/rtl`). |
| LCL | Lazarus Component Library | GUI component library targeted by the GTK frontend (`lib/lcl`). |
| LFM | Lazarus Form Module | `.lfm` text resource describing a streamed component tree. |
| RTTI | Run-Time Type Information | Reflection data emitted for `published` members. |
| ARC | Automatic Reference Counting | Managed-string / managed-record lifetime model. |
| COW | Copy-On-Write | String/array sharing until first mutation. |
| VMT | Virtual Method Table | Per-class dispatch table for virtual methods. |
| IMT | Interface Method Table | Dispatch table for interface methods. |
| FFI | Foreign Function Interface | Calling into external (C) code. |

## ABI, Linking, And Binary Format

| Term | Expansion | Notes |
|------|-----------|-------|
| ABI | Application Binary Interface | Calling convention, layout, and register usage rules. |
| ISA | Instruction Set Architecture | The CPU instruction set a target emits for. |
| ELF | Executable and Linkable Format | The output binary format on Linux. |
| BSS | Block Started by Symbol | Zero-initialized data segment. |
| GOT | Global Offset Table | Indirection table for position-independent symbol access. |
| PLT | Procedure Linkage Table | Lazy/indirect call stubs for external functions. |
| PIC | Position-Independent Code | Code that runs regardless of load address. |
| SIB | Scale-Index-Base | The x86-64 addressing byte after a ModRM. |
| TLS | Thread-Local Storage | Per-thread variable storage. |
| API | Application Programming Interface | A library's callable surface. |

## Platform And Hardware

| Term | Expansion | Notes |
|------|-----------|-------|
| CPU | Central Processing Unit | |
| RAM | Random Access Memory | |
| MMU | Memory Management Unit | Address translation hardware. |
| SSE | Streaming SIMD Extensions | x86 floating-point / vector unit (C-call ABI support pending). |
| AVX | Advanced Vector Extensions | Wider x86 SIMD. |
| RISC | Reduced Instruction Set Computer | e.g. the planned RISC-V target. |
| ARM | (Advanced RISC Machines) | Planned aarch64 / arm32 targets. |
| AVR | (Atmel 8-bit MCU family) | Candidate bare-metal target class. |
| RTOS | Real-Time Operating System | Optional hosted hook for the allocator. |
| QEMU | Quick Emulator | Used to run cross-compiled targets. |
| IEEE | Institute of Electrical and Electronics Engineers | As in IEEE 754 floating point. |

## Toolchain And Ecosystem

| Term | Expansion | Notes |
|------|-----------|-------|
| GCC | GNU Compiler Collection | |
| GLIBC | GNU C Library | |
| GNU | GNU's Not Unix | |
| POSIX | Portable Operating System Interface | |
| GTK | GIMP Toolkit | The widgetset backing the LCL-compatible GUI. |
| GUI | Graphical User Interface | |
| TUI | Text User Interface | |
| CLI | Command Line Interface | See [`cli.md`](cli.md). |
| IDE | Integrated Development Environment | |
| COM | Component Object Model | Reference model for the interface design. |
| GC | Garbage Collection | Contrasted with this project's ARC approach. |
