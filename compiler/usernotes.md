user notes.

---

## Project identity and conditional compilation (implemented 2026-05-27)

The provisional compiler name is **PXX**. It is deliberately provisional; the
binary remains `compiler/pascal26` until a name is stable enough to rename seed
and history-related artifacts.

PXX now predefines `PXX` for Pascal source and does **not** predefine `FPC`.
Accepted conditional directives:

```pascal
{$define NAME}
{$undef NAME}
{$ifdef NAME}
{$ifndef NAME}
{$else}
{$endif}
{$mode objfpc}
```

Command-line inputs implemented now are `-dNAME`, `-uNAME`, `-Mobjfpc`, and
`--strict-overload`. The mode spelling is accepted as a compatibility marker;
multiple semantic modes do not exist yet. Compiler bootstrap code may
continue to use `{$ifdef FPC}` where the branch genuinely depends on Free
Pascal as the host.

Compatibility and missing-feature status is maintained in `COMPATIBILITY.md`.

---

## Language dialect / compiler switches (2026-05-27)

We are extending Pascal beyond standard — crafting a superset/dialect, not a subset.
Features that deviate from standard Pascal should be controllable via compiler switches
so users can opt in/out of non-standard behaviour.

Proposed feature-switch syntax beyond the implemented conditional layer:
```pascal
{$SWITCH_NAME value}
```

Or command-line flag:
```
pascal26 --switch=value source.pas output
```

### Switch state

**`strict_overload`** (implemented; default: off)
- Off: overloading works without `overload` directive — compiler silently accepts both
  `procedure Foo(x: Integer)` and `procedure Foo(x: Char)` side by side.
  The `overload` keyword is accepted but ignored.
- On via `{$strict_overload on}` or `--strict-overload`: requires explicit
  `overload` directive on all overloaded variants (standard Delphi/FPC behaviour).
  Useful for codebases that want strict Pascal compatibility.

**`generic_syntax`** (default: `b1`)
- `b1`: top-level `generic function`/`specialize ... as` — chosen syntax (see below).
- `a`: type-section `generic TName<T> = function ...` — alternative, more class-consistent.
- `b2`: call-site specialization `Max<Integer>(...)` — future sugar on top of b1.

More switches will be added as dialect features grow.

---

## Generic Functions — Decision: B1 (2026-05-27)

**Chosen: Proposal B1.** Proposal A kept as alternative. B2 as future sugar.

### B1 — Chosen syntax

```pascal
{ Definition at top level }
generic function Max<T>(A, B: T): T;
begin
  if A < B then Result := B else Result := A;
end;

generic procedure Swap<T>(var A, B: T);
begin
  var tmp: T;
  tmp := A; A := B; B := tmp;
end;

{ Specialization at top level, explicit named }
specialize Max<Integer> as MaxInt;
specialize Max<Char>    as MaxChar;
specialize Swap<Integer> as SwapInt;

{ Call — just normal functions }
begin
  writeln(MaxInt(3, 7));
  writeln(MaxChar('a', 'z'));
  SwapInt(x, y);
end.
```

**Why B1 over A:**
- Functions stay at top level where functions live — cleaner mental model.
- `generic function` reads naturally.
- `specialize ... as Name` gives full naming control.

**Why B1 over B2:**
- B1 specializes at a top-level declaration point — parser is in clean state.
  Inject and compile the specialized body right there. Done.
- B2 forces detection mid-expression, requires forward registration + deferred
  body compilation — more complex machinery, more edge cases.
- B2 can be layered on top of B1 later as pure syntactic sugar:
  `Max<Integer>(a, b)` desugars to `specialize Max<Integer> as Max_Integer` (once)
  then `Max_Integer(a, b)`.

### Proposal A — Alternative (not chosen, kept for reference)

```pascal
type
  generic TMax<T> = function(A, B: T): T
  begin
    if A < B then Result := B else Result := A;
  end;

  MaxInt = specialize TMax<Integer>;
```

Consistent with class generics. Body inside `type` section is non-standard.
Implement if `{$GENERIC_SYNTAX a}` is requested.

### Proposal B2 — Future sugar (not yet implemented)

```pascal
writeln(Max<Integer>(3, 7));
```

Desugars at call site. Requires lookahead `Ident < Type > (` inside expression.
Only safe because `(Bool) > (fn-call)` is not a valid expression — parser can
distinguish without `FindGenericFunc` lookup. Implement after B1 is stable.

---

## Operator Overloading (implemented 2026-05-27)

Generic functions like `Max<T>` use `<` and `>` on `T`. For built-in types
(Integer, Char) this works because codegen knows those operators. For user-defined
types (records, classes), it breaks — the compiler has no way to emit `<` for
an unknown type.

Operator overloading solves this: user defines `operator <(a, b: TMyType): Boolean`
and the compiler emits a call to it wherever `<` is used on that type.

**Supported syntax** (Delphi-style):
```pascal
operator < (a, b: TVector): Boolean;
begin
  Result := a.Magnitude < b.Magnitude;
end;
```

Implementation uses an operator-to-procedure table keyed by operator token,
operand type and class/record id. Binary AST code generation checks this table
before built-in emission and generates a normal call when matched.
`test/test_op_overload.pas` covers `<`, `>`, `=`, and `+`.

Routine overload declarations accept Delphi/FPC-style `overload;`. It remains
optional by default; `{$strict_overload on}` or `--strict-overload` enforces it.

## Loop Control (implemented 2026-05-27)

`break` and `continue` are supported for Pascal `while`, `for`, and `repeat`
loops. Code generation maintains nested-loop jump fixups; `continue` targets
the `for` update step and the `repeat` condition. Coverage is in
`test/test_loop_control.pas`.

---

so, lexer seems to be purely language specific. that is actually a good choice. we will not abstract all lexing, yet just optimize a hardcoded lexer per language. i think that's ok and sane and also the fastest.

about parser. first off, i have the impression some pascal syntax leaked into here. obviously our ideal parser is languange-agnostic. but maybe we do need hints etc, so i admit this disntinction lexer/parser is fuzzy. now, the other track is, parser now targets single system single cpu. a lot of that could be abstracted away. while we still can focus single os, single cpu family. 

the other remark about lexer. it is really short. and a lot of that space is even wasted on code that is severly shortened if we had some library utils for string parsing, finding, indexing or mapping. so for now, code works, it is ok, but we might want to look into this. as it does require language features.


(AI comment):about IR generation. it does have a lot of pascal syntax leaked into here too. this is fine for now. since we only use it as a seed to bootstrap. but as we grow, we will likely want to refactor this part of the compiler. 

explain what IR generation does now. this is some kind of intermediate representation of the source code for the assembler generation phase.

what the IR generation does now: it basically translates the AST into a series of instructions that can be executed by the target machine.

[that is what the user mentioned about the parser. define IR. for a sec.]

that is also a part where we can abstract away stuff. we can make IR more portable. even more abstract.     
define the letters IR.
(AI comment): IR stands for Intermediate Representation. It's a way to represent the source code in a format that is easier to work with than the original source code. It's also more portable than the original source code, as it can be used to generate code for different target machines.
user apologizes for not knowing compiler internal slang. (AI:) now that he does, he is wondering if he should change the name of the project. (user:) he does not. combining C and pascal as single compilable easyfies the world.        


i think we should refactor lexer. i do not like the big switch, the string indexing...     

why we do not write a lexer that generates tokens and returns them. this way the parser does not need to know about the lexer.  

why we do not write a parser that generates tokens and returns them. this way the IR generator does not need to know about the parser.  

i think we should refactor parser. i do not like the big switch, the string indexing...     user agrees/ lexer should generate abstract tokens.




the parser should generate an abstract syntax tree (AST). This AST is a tree representation of the source code that is independent of the source language. The AST is then used to generate the IR.
user agress. you are the expert, i am just designing a weird goal. a cross language compiler.

keep into mind that from now on we should be self hosting. any regression and falling back to fpc is acceptable, yet shame on us.

the compiler can self compile. that is a major milestone. we do not need fpc.

let me explain why the choice for pascal was right, in a way. even in afterthought. and unconsiously made. so, object pascal t is a sortof superset of C. C++ has syntactic hacks, similar superset. now, on the other end, python. pascal has string/buffer handling. reflection. we sortof sit in the middle, something that can be compiled, yet fancy features. C# also a beautiful language and i never understood why we need a VM per se. libraries, yes. but vm, why not native code. etc.

(AI:) python: super easy to read and write. dynamic. hard to make portable. hard to make fast. yet easy to make. with good enough libs.  








---

## Generic Functions — Design Proposals (2026-05-27)

Status: **undecided** — leaning A. Implement A first, leave B for later.

---

### Proposal A — Type-section (consistent with class generics)

Definition inside `type` block, body attached inline:

```pascal
type
  generic TMax<T> = function(A, B: T): T
  begin
    if A < B then Result := B else Result := A;
  end;

  generic TClamp<T> = function(V, Lo, Hi: T): T
  begin
    if V < Lo then Result := Lo
    else if V > Hi then Result := Hi
    else Result := V;
  end;

  generic TSwap<T> = procedure(var A, B: T)
  begin
    var tmp: T;
    tmp := A; A := B; B := tmp;
  end;
```

Specialization inside `type` block, user-chosen name:

```pascal
type
  MaxInt   = specialize TMax<Integer>;
  MaxChar  = specialize TMax<Char>;
  ClampInt = specialize TClamp<Integer>;
  SwapInt  = specialize TSwap<Integer>;
```

Call like any regular function/procedure:

```pascal
begin
  writeln(MaxInt(3, 7));         { → 7 }
  writeln(ClampInt(15, 1, 10));  { → 10 }
  SwapInt(x, y);
end.
```

**Pros**
- Identical pattern to class generics: `generic Name<T> = ...`, then `specialize`.
- Explicit user-chosen name — no generated `Max_Integer` noise.
- `specialize` stays inside `type` sections — parser path already exists.
- `<>` never appears near operators — zero ambiguity risk.
- Multiple specializations of same template possible in one `type` block.

**Cons**
- Function body inside `type` section is non-standard Pascal.
- More verbose — requires `type` block for both definition and specialization.
- `ParseTypeSection` needs extension to handle `function`/`procedure` bodies with `begin...end`.

---

### Proposal B — Top-level modifier

Definition at top level, `generic` as modifier on `function`/`procedure`:

```pascal
generic function Max<T>(A, B: T): T;
begin
  if A < B then Result := B else Result := A;
end;

generic procedure Swap<T>(var A, B: T);
begin
  var tmp: T;
  tmp := A; A := B; B := tmp;
end;
```

Specialization with optional rename:

```pascal
specialize Max<Integer>;              { generates Max_Integer }
specialize Max<Integer> as MaxInt;    { generates MaxInt }
specialize Swap<Integer>;
```

Call:

```pascal
begin
  writeln(Max_Integer(3, 7));  { or MaxInt(3, 7) if renamed }
end.
```

**Pros**
- Functions stay at top level where functions live.
- `generic function` reads naturally.
- Shorter definition syntax.
- `specialize ... as` gives optional rename without a `type` block.

**Cons**
- `specialize` at top level is new — currently only inside `type` sections.
- Auto-generated names (`Max_Integer`) are ugly without `as` rename.
- Call-site `Max<Integer>(...)` sugar is ambiguous: parser must look ahead
  past `<`/`>` that also serve as comparison operators.
- Two separate `specialize` parse paths (top-level vs. inside `type`).

---

### Ambiguity note: `<>` at call site (Proposal B only)

`writeln(Max<Integer>(3,7))` — parser sees:

```
Max  <  Integer  >  (  3  ,  7  )
```

versus expression `(Max < Integer) > (3, 7)` — only distinguishable by knowing
`Max` is a generic. Safe if `FindGenericFunc(name)` is checked first with lookahead
`Ident < Ident > (`. Risk: variables/functions named `Max` would shadow it.
Proposal A avoids this entirely — `<>` only in `type` sections.

---

### Future: compiler switch

Both could coexist under a pragma:

```pascal
{$GENERIC_SYNTAX type}      { Proposal A — default }
{$GENERIC_SYNTAX toplevel}  { Proposal B }
```

Or detect context automatically: `generic` inside `type` → A-style;
`generic function` at top level → B-style. Token-buffer machinery is shared either way.

---

### Implementation notes (shared)

- Reuse `TemplateTokens` / `SpecializeStream` — same substitution engine as class generics.
- `TGenericFunc` record: `Name`, `Param`, `IsFunc`, `TokStart`, `TokCount`.
- `specialize TMax<Integer>` for functions: `SpecializeStream` → `ParseSubroutine`
  (same pattern as `BufferGenericMethod` for class methods).
- `FindProcOverload` in `ParseSubroutine` handles re-use of forward declarations.
- `ScanGenericFuncSig`: scans buffered tokens to extract param types for forward registration.

---

2026-05-27 — FPC BOOTSTRAP USED for generic function implementation

Added TGenericFunc and TPendingGFSpec record types to defs.inc. Old seed
didn't know them (symtab.inc hardcodes all record types). Same situation as
2026-05-25. Bootstrap completed: FPC → gen1 → gen2 → gen3 fixedpoint. All tests pass.

---

2026-05-27 — FPC BOOTSTRAP USED for overload and loop-control stabilization

Operator overloading initially introduced `Break` into compiler source before
the self-hosted seed supported it. Recovery replaced those internal uses with
Boolean termination, stabilized generic specialization through global scratch
tokens, and added routine `overload;`, `break`, and `continue` support.
Bootstrap completed: FPC → gen1 → gen2 fixedpoint. `make test` passes.

---

2026-05-25 — FPC BOOTSTRAP USED (deliberate cheat, noted for the record)

Stage 1 refactor (token stream buffering) introduced TRawToken, a new record type that the existing self-hosted seed did not know about (symtab.inc hardcodes all record types). The old seed could not compile the new source, so we fell back to `make bootstrap` to regenerate the seed via FPC.

This is not a sin. FPC bootstrap is the defined recovery path. After bootstrapping, the compiler was fully self-hosting again: new seed compiled itself 3 generations to fixedpoint, all 36 tests passed.

Going forward: prefer staying self-hosted between iterations. When a change requires new record types or language features not yet in the seed, bootstrap is acceptable — but note it here. Goal is that FPC bootstrap becomes increasingly rare as the compiler grows.
