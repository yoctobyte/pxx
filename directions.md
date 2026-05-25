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
- normal development builds are self-hosted: `make` rebuilds through the existing `compiler/pascal26` seed and checks a recursive fixed point before installing it
- `make bootstrap` is the recovery path: FPC creates a seed, which must still reach the same recursive fixed point before it replaces the working compiler
- `make test` also runs `make fpc-check` coverage so the compiler source remains FPC-compatible
- compiler source uses only stable language features: a feature is stable for self-hosting after it passes the recursive bootstrap checks; new features remain in tests until then

## At the horizon
- Frankenstein compiler. a bunch of useful (yet compatible languages) in the same code base. including stuff like Rust. Now, we don't have to be accurate as rust, we just have to compile the code. Other suggestions are SQL (!), bash??, etc. For names we are considering like "Frankenpile" or "Francompiler" or. But Fran is a name and a common known youtube personality. Other names always open for suggestion. Yet for now we keep our implementation in pascal, as that ought to be universal enough and sortof makes sense to build a frankstein compiler out of a single language. although surely we hope the day will come that we say 'if we write this in this other language, it gets 50% shorter. or more readable'. etc.
- 1-step compile. internally we still would have our tools. but keeping it all in-memory should make it fast. Rust compiler good example for how we can be fast. Maybe see what their approach is and steal ideas. 
- JIT compiling another thing. not for the JIT. but for how to combine multiple language/data/memory/namespace barriers. 

## Other notes
- We would like to keep the moment we reached self-compiling. for historic record.
- We would like to keep the main project in pascal. And target fpc compatibility (as in: fpc should be able to compile our pascal source dialect).
- For self-hosted. For the moment we will rely on pascal source only. Any other language only as tests. This may or may not change in the future. Since the nature of the project, it may change. For now, all source code would be in valid/semistandard Pascal.


.
