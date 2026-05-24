goal: create a self hosting pascal compiler, evolving into a "frankenstein" multi-language compiler.

## bootstrap
- bootstrap using fpc (Free Pascal) and gpc (GNU Pascal) — both available
- keep bootstrap binaries for historic reference once self-hosting achieved
- self-hosting as soon as possible

## language targets (priority order)
1. Pascal (Free Pascal compatible) — primary
2. Object Pascal — primary
3. C — primary (interop + library use is core value)
4. C++ — limited/partial support
5. Python, JavaScript, C# — limited/experimental

## killer feature: multi-language
- libraries usable at will across languages (e.g. call a C lib from Pascal, a Pascal unit from C)
- .mix files: mix languages in a single source file (experimental, complex, high potential)
- "frankenstein" philosophy: best tool for the job, not ideological purity

## compiler design
- no complicated lexer, no cumbersome linking steps
- everything in-memory: build ELF binary in RAM, write executable directly
- no external assembler, no linker
- no external libraries in the compiler itself (compiler is self-contained)

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


