goal: create a self hosting pascal compiler, evolving into a "frankenstein" multi-language compiler.

## bootstrap
- bootstrap using fpc (Free Pascal) and gpc (GNU Pascal) — both available
- keep bootstrap binaries for historic reference once self-hosting achieved
- self-hosting as soon as possible

## language targets (priority order)
1. Pascal (Free Pascal compatible) — primary
2. Object Pascal — primary
3. C — primary (interop + library use is core value)
4. Basic — high interest
5. Ada — high interest
6. C++ — partial/limited
7. Fortran — partial/limited
8. COBOL — partial/limited
9. Java — partial/limited (JVM-less native compilation goal)
10. C#, JavaScript, Python — experimental

## killer feature: multi-language
- libraries usable at will across languages (e.g. call a C lib from Pascal, a Pascal unit from C)
- .mix files: mix languages in a single source file (experimental, complex, high potential)
- "frankenstein" philosophy: best tool for the job, not ideological purity

## compiler design
- no lex/yacc/ANTLR or any external grammar tools — hand-rolled recursive descent parsers only
- no cumbersome linking steps — everything in-memory, write ELF directly
- no external assembler, no linker
- compiler itself: zero external dependencies, zero licensing issues — 100% own code
- architecture: per-language frontend → common IR → shared backend
  - each language gets its own lexer + recursive-descent parser
  - all frontends emit into one common IR
  - one backend: x64 codegen → ELF writer (ARM64 etc. added later)
- "avoid complicated lexer" means: no generator tools, no grammar files, no table-driven DFAs
  hand-written scanners are fine and encouraged (simple, fast, no deps)

## targets
- primary: ELF x86-64 Linux
- secondary: ARM64, 32-bit
- non-POSIX: not yet, but architecture abstraction from the start
- embedded of interest: ESP32 and similar (no OS, bare metal)
- aim: better than Arduino's mixed bag, better than MicroPython VM overhead

## process
- git commit at each step
- cross-compiler capability from the start
- direct (native) build also from the start


