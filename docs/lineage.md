# Lineage and Acknowledgements

This compiler exists because of the people listed here. Every design choice,
every feature, every line of source code is downstream of their work.

---

## The First Programmer

**Ada Lovelace** (1815–1852) wrote what is considered the first algorithm — a
method for computing Bernoulli numbers on Charles Babbage's Analytical Engine,
a machine that was never built in her lifetime. She understood that a machine
capable of manipulating symbols could do more than arithmetic. That insight is
the foundation of everything that followed.

The Ada programming language is named in her honour.

---

## The Foundations (1950s)

- **John Backus** and the IBM team — **FORTRAN** (1957). The first widely used
  high-level language. Proved that compiled code could be fast enough for
  real work. The field has not stopped arguing about it since.
- **Grace Hopper** and team — **COBOL** (1959). Proved that programs could be
  readable by people who were not mathematicians. Hopper fought for that idea
  when most of the field did not believe it.
- **John McCarthy** — **Lisp** (1958). Garbage collection, recursion as a
  first principle, code as data. Decades ahead of everyone else and still
  teaching lessons.
- **John Kemeny and Thomas Kurtz** — **BASIC** (1964, Dartmouth). Designed to
  be accessible to students with no prior experience. The first language for
  millions of people.

---

## Two Lineages from One Root

**ALGOL 60** (1960) — designed by an international committee including
**Peter Naur**, **John Backus**, and others. Block structure, lexical scoping,
formal grammar (BNF). Nearly every language since is a descendant, one way
or another.

### The Pascal Branch

**Niklaus Wirth** — **Pascal** (1970). Clean, structured, strongly typed.
Designed to teach good programming practice. Turned out to also be excellent
for real software.

**Niklaus Wirth** and **Larry Tesler** (Apple) — **Object Pascal** (1986).
Object-oriented extensions to Pascal. The language that powered the early Mac.

**Anders Hejlsberg** (Borland) — **Turbo Pascal** (1983). Made Pascal fast to
compile, cheap to buy, and accessible to everyone. Hejlsberg later designed
C# and TypeScript. His compiler work shaped what compilers can be.

**Borland** — **Delphi** (1995). Object Pascal with a visual IDE. Defined
component-based development for a generation.

**The Free Pascal team** — **FPC** (1993–present). Kept Pascal alive, open,
and cross-platform after the commercial era ended. Multi-architecture,
actively maintained. Without FPC, this project has no bootstrap path.

**The Lazarus team** — **Lazarus** (1999–present). An open-source
Delphi-compatible IDE built on FPC. Kept the whole ecosystem healthy. Love
and respect.

### The C Branch

**Martin Richards** — **BCPL** (1967). Typeless, direct, the ancestor of
everything below.

**Ken Thompson** — **B** (1969, Bell Labs). BCPL stripped for the PDP-7.

**Dennis Ritchie** — **C** (1972, Bell Labs). Added types, became the language
of Unix, then of everything. Sharp, honest, and unforgiving. We love it.

**Bjarne Stroustrup** — **C++** (1983). Classes, templates, RAII. The language
that set out to have everything.

---

## Ada

**Jean Ichbiah** and team — **Ada** (1980, DoD). Commissioned to replace a
zoo of incompatible languages across US defense systems. Strongly influenced
by Pascal and ALGOL 68. Strong typing, packages, built-in concurrency,
exception handling in the spec. Named for Ada Lovelace. Consistently
underappreciated.

---

## BASIC and the PC Era

**Bill Gates and Paul Allen** — **Microsoft BASIC** (1975) and **GW-BASIC**
(1983). Put a programming language in the hands of everyone who bought a
personal computer. Millions wrote their first program in GW-BASIC. That
matters more than it is usually credited for.

---

## Everyone Who Came After

**Niklaus Wirth** — **Modula-2** (1978) and **Oberon** (1987). Kept
demonstrating that a language can be small, clean, and powerful all at once.

**Guido van Rossum** — **Python** (1991). Readable above all else.

**Graydon Hoare** — **Rust** (2010). Memory safety without a garbage
collector. The borrow checker is a genuinely brilliant piece of engineering.

**The GNU project**, **LLVM**, **GCC** teams — the infrastructure the whole
industry builds on.

Every language designer. Every compiler writer. Every open source maintainer
who kept a tool alive past its commercial era. This project is downstream of
all of it.

---

## The Authors of This Project

**PXX / Frankonpiler** is what happens when a human rambles about wanting a
Frankenstein compiler and several AI assistants — OpenAI Codex, Anthropic
Claude, and Google Gemini — attempt to interpret that rambling as source code.

The vision, the direction, and the stubborn conviction that Pascal is
underrated were human. The code is AI's best guess at what was meant.

Ada Lovelace would have had opinions about this.

*(This is a joke. The human was genuinely involved. The compiler works.
These facts are not in conflict.)*

Ada, love ya.
