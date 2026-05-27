goal: create a self hosting pascal compiler, evolving into a "frankenstein" multi-language compiler.

Working project/compiler identity: **PXX** (provisional; may be renamed before
public stabilization). PXX defines `PXX`, never implicitly `FPC`; FPC
compatibility modes describe source behavior, not compiler identity.

## bootstrap
- **Self-evolution**: Avoid bootstrapping using FPC by default. The compiler should self-evolve using its own built self-hosted compiler binary (`compiler/pascal26`). FPC remains a secondary tool to verify compatibility.
- bootstrap using fpc (Free Pascal) and gpc (GNU Pascal) — kept only as verification / backup path
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


## Compatibility considerations
- Since we want FPC to be able to compile our Pascal source dialect, we should try to stay as close to FPC as possible. 

This may be a difficult line to walk. However if fpc is to ever compile our source, we need to be careful with what we do. 
FPC can target many architectures. That is valuable. Then again, we aim for a frankenstein compiler. Where we could include C or BASIC or perl or whatever language solves the issue in cleanest code. Not only to import libraries, but to also provide clean and readable code. We allow ourselves to only support subsets of languages, or even non-standard features of those languages.


- (AI suggestion) since the project is called "frankenstein compiler" we should allow ourselves to be creative and make some changes to pascal. -- User: No. We will try to keep our pascal source code dialect compilable by FPC. At least for the time being. Supported language and dialects is another issue than the actual language the compiler is written in. However indeed as project evolves, and has stable targets/hosts, we may consider writing parts of the compiler in other languages. However, right now targeting other cpu architectures and having 32/64 bit choice is more relevant. As for your suggestion, yes if we want to redefine Pascal, that is an interesting goal. But we would clearly mark that as another dialect.

(user:)› good. so advice what should be next. fancy features? more language? i sortof agree that we can keep our compiler minimal. bootstrappable. there is no need to use other languages or OOPS features. pretty
  much the same way how C serves us. And notice that i never said 'C++'. even if some say 'that are just macro's on top of C'. well if so, ok. it'd be just source code. but my guts say we rather implement
  Rust than C++. i am also proud we can use all standard libraries at will. that is really good progress. so. advice please


(ai:)• I would not add another language now. The highest-value direction is to make the compiler an excellent small native core that can consume the platform around it.

  One correction: you can reach libc now, which is important, but not yet “all standard libraries at will.” Many headers and APIs require pointers, buffers, typedefs, structs, constants, callbacks,
  variadics, library mapping, and stronger preprocessing. That is the productive frontier.

  Recommended Direction

  1. Turn C interop into a dependable foreign-function layer
      - Explicit library import syntax instead of ctype -> libc.so.6 special cases.
      - Pointer arguments and return values.
      - Mutable buffers and C strings.
      - size_t, fixed-width integer aliases, common typedef handling.
      - Struct layout for simple records.
      - Better diagnostics for unsupported declarations.

     This immediately unlocks real APIs: string.h, unistd.h, math.h, file APIs, time APIs, terminal APIs, sockets, SQLite, SDL subsets, and more.
  2. Keep improving preprocessing only when real headers demand it
      - Macro rescanning.
      - Hex/suffix/arithmetic evaluation in #if.
      - Function-like macro nesting.
      - Later: ##, #, variadic macros only if encountered.

     Do not aim for abstract ISO C completeness yet. Use installed headers as the test corpus.
  3. Add debugging support before adding language breadth
      - A generated map file or ELF symbol table for procedure addresses.
      - Optional source-line mapping later.
      - Keep --debug for compiler tracing; add symbol output for generated-program debugging.

     This will pay for itself every time the bootstrap compiler miscompiles something.
  4. Protect the bootstrappable core
      - Keep the implementation in the small Pascal subset the compiler already handles reliably.
      - Add self-hosted regressions for every new ABI/header feature.
      - Avoid language features that complicate the compiler without unlocking external capability.

  About More Languages

  BASIC and Pascal are already enough to demonstrate multiple frontends. Finishing their existing work is reasonable, but starting a third frontend now would dilute the most distinctive result: native
  access to existing system libraries without glue.

  Rust would be a poor next implementation target despite being a better-designed language than C++. Useful Rust requires ownership checking, traits, generics, enum layout, slices, lifetimes, substantial
  runtime/ABI decisions, and integration with its ecosystem. A tiny Rust-shaped language would not buy you actual Rust library access.

  C++ is worse for this project goal. “Macros on top of C” is not a useful model of modern C++: overloading, name mangling, constructors/destructors, templates, exceptions, RTTI, references, object ABI,
  and the standard library make interoperability very large and platform-specific.

  What I Would Build Next

  A small, explicit C import model, for example conceptually:

  uses libc('string.h', 'libc.so.6');

  Then target these milestones:

  1. Call strlen with a Pascal string converted to a C pointer.
  2. Call puts.
  3. Call memcpy with buffers.
  4. Import simple constants and typedef aliases from headers.
  5. Call open/read/close through imported declarations.
  6. Add libm.so.6 and call abs or integer-friendly functions first, then floating-point support when the compiler is ready.

  That path keeps the compiler minimal while expanding what programs can actually do. It is the same strength C has: a small language surface attached to a large, usable operating-system ecosystem.

  (USER:) we can hardcode special cases for libc. 

  (AI)› so we don't need to support all of libc. We only need to support those cases we encounter. See how far we can get with some smart preprocessing. And whatever is missing, we hardcode. So we can still claim that 'we don't support C' while indeed we do support most of C. And we can even support C++? 

  (USER:) we would like to avoid all translation overhead. pascal programs just import c headers. as for C++, we don't care.. Javascript would be more useful. C++ too complicated. It is fantastic. But not what we are seeking. Maybe, later, once we solved the rest. Part of that issue is all the complexity. Any new designed language like C# or Java is easier than C++. C++ requires that whole toolchain, as-is. 
  
  (AI): A frankenstein compiler is something that supports multiple languages and frontends, and can mix and match their code.  
  (user) we didnt even reach full object pascal compatibility yet. or a full c preparser. 
  (AI): 


  


