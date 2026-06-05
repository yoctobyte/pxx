# Lineage And Acknowledgements

PXX is a small project, but it sits on a long chain of language design,
compiler engineering, operating-system work, and open-source maintenance. This
page records the main influences and dependencies. It is not a complete
history of programming languages.

## Early Foundations

**Ada Lovelace** (1815-1852) described an algorithm for Charles Babbage's
Analytical Engine and recognized that a symbolic machine could manipulate more
than numbers. The Ada language is named in her honor.

**FORTRAN** (John Backus and the IBM team, 1957) proved that compiled
high-level languages could be practical for scientific and engineering work.

**Lisp** (John McCarthy, 1958) introduced ideas that still shape language
design: symbolic computation, recursion as a central tool, automatic memory
management, and code as data.

**COBOL** (Grace Hopper and collaborators, 1959) helped establish programming
as a business tool and argued for source code that domain experts could read.

**BASIC** (John Kemeny and Thomas Kurtz, 1964) made interactive programming
accessible to students and later to millions of personal-computer users.

## ALGOL And Structured Programming

**ALGOL 60** introduced block structure, lexical scoping, and a formal grammar
notation through Backus-Naur Form. It is one of the main ancestors of modern
structured programming languages.

**Niklaus Wirth** carried that tradition through Pascal, Modula-2, and Oberon:
small languages, clear type systems, explicit structure, and compilers that can
be understood by working programmers. PXX is particularly close to that
tradition: it prefers a simple bootstrap compiler over a large, opaque toolchain.

## Pascal, Object Pascal, FPC, And Lazarus

**Pascal** (Niklaus Wirth, 1970) combined a clean syntax, strong typing, and
structured programming. It was designed for teaching but proved useful far
beyond the classroom. The language is named for **Blaise Pascal**, the
mathematician and inventor of the Pascaline mechanical calculator.

**Object Pascal** brought object-oriented programming into the Pascal family.
Apple's Object Pascal work and later Borland's Delphi lineage made classes,
properties, components, and visual application development central to the
ecosystem.

**Turbo Pascal** (Anders Hejlsberg and Borland, 1983) showed how much a fast,
integrated compiler could change day-to-day programming. Delphi later extended
that lesson into a full component-oriented development environment.

**Free Pascal (FPC)** keeps Pascal portable, open, and actively maintained. It
is PXX's bootstrap and recovery compiler, and `make fpc-check` exists to keep
that path healthy.

**Lazarus** keeps the Delphi-style ecosystem viable on top of FPC. PXX's RTTI,
published-property, component-streaming, and LFM work are directly informed by
that ecosystem.

## C, Unix, And Native Interop

**BCPL** (Martin Richards), **B** (Ken Thompson), and **C** (Dennis Ritchie)
form the lineage behind Unix and much of today's systems software. C's direct
mapping to native interfaces is why PXX treats C imports as a first-class
compiler concern rather than a wrapper-only afterthought.

Unix, POSIX, ELF, and the System V AMD64 ABI define much of PXX's current
target environment. The compiler emits Linux x86-64 ELF directly and calls
selected shared-library symbols without invoking a system linker.

**C++** (Bjarne Stroustrup) is not a current PXX target, but its influence is
unavoidable: templates, RAII, and decades of systems programming practice shape
the surrounding ecosystem PXX must interoperate with.

## Ada And Strong Systems Languages

**Ada** (Jean Ichbiah and team, 1980) was designed for large, safety-critical
systems with strong typing, packages, exceptions, and concurrency in the
language specification. It is an important reminder that systems languages can
be rigorous without being minimal.

## Later Language Influences

**Microsoft BASIC** and **GW-BASIC** put programming in front of many early
personal-computer users. They matter here because accessibility is part of a
language's impact, not a side detail.

**Python** (Guido van Rossum, 1991) is a major influence on readability and on
PXX's experimental Nil Python frontend. PXX does not try to reproduce CPython;
it explores a small, statically compiled Python-like surface.

**Rust** (Graydon Hoare and the Rust project, 2010) shows that memory safety and
native code are not opposing goals. PXX is not a Rust compiler, but Rust's
ownership discipline is relevant whenever this project discusses managed
values, borrowing, and embedded targets.

The **GNU**, **GCC**, **LLVM**, **Linux**, and broader open-source communities
provide tools, documentation, ABIs, reference implementations, and decades of
accumulated practice.

The Pascal tradition is part of that larger history: small compilers, readable
source, strong typing, native code, practical tooling, and careful bootstrap
discipline. That context is the reason these acknowledgements belong here.
