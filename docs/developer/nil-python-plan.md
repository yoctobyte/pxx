# Plan: "Nil Python" (No/Not Python) frontend for frankonpiler

## Context

The compiler ships a BASIC demo frontend, but BASIC is a poor showcase: verbose, dated
grammar. We want a **Python-shaped** frontend instead — short, readable code, clean grammar
— without paying for CPython's dynamic-everything machine. Full Python is a non-goal (no
`eval`, no self-modification, no open runtime type universe). Like MicroPython/RPython/Boo/
Genie/Nim, this is a *somewhat-compatible dialect*, named **"Nil Python"** (No/Not Python).

Source extension: **`.npy`** ("Nil pY"). `.py` stays unsupported on purpose — accepting it
would imply broader Python compatibility than the dialect intends. Editor tooling can map
`.npy` to Python syntax highlighting.

### Core design decision (settled)

**Statically typed, with local type inference and a closed scalar-Variant escape valve.**
Every var starts statically typed (inferred from first binding). The checker unifies types
across rebinds:

- common static type exists (numeric widening only — *no* JS-style coercion) → stay unboxed.
- unify fails but both sides fit a fixed scalar set → **promote slot to `tyVariant`**.
- unify fails and a side doesn't fit (arbitrary class/record) → **compiler says no** (clear error).

"Proper code is single-typed; Variant is the escape valve inference reaches for, not the
default." 95% of code stays unboxed and compiles to fast native via the existing IR.
`tyVariant` is a **closed scalar escape hatch, not an open top type** — incompatible records,
arbitrary classes, and dynamic attributes stay compile-time errors until an explicit boxing
tier is designed.

### Why this is tractable

A frontend here is only **lexer + parser that build the shared AST**, then call
`CompileAST()`. BASIC is ~620 lines and even borrows Pascal's `ParseExpr`. The whole backend
— linear IR, x86-64 emission, ELF — is shared. There is no register allocator. The remaining
cost is mostly *semantics*, handled by the phasing below.

### Reusable machinery already present (verified)

- Frontend dispatch by file extension — `compiler/compiler.pas:134` (`isC`/`isBasic`), parse handoff `:182`.
- Shared AST node kinds — `compiler/defs.inc:62-112`; build via the same nodes BASIC uses.
- `CompileAST()` handoff — `compiler/ir_codegen.inc:1989` (`IRReset; IRLowerAST; IRVerify; IREmitMachineCode`).
- **`tySet` precedent** for a value-type-with-special-ops — `compiler/defs.inc:299`, `IR_SET_LIT/COPY/BINOP/CMP` `:154-163`. `tyVariant` follows the same aggregate-value discipline while keeping its IR additions small.
- **Operator overloading already works** — `ParseOperatorDef` `compiler/parser.inc:558` (`operator < (a,b: TMyType): Boolean`). Variant/box behavior lives in RTL, not the compiler.
- **Virtual dispatch (VMT)** — `IR_VIRTUAL_CALL`; classes map straight onto this.
- Type sizing — `TypeSize` `compiler/symtab.inc:683`.
- Heap (`GetMem/FreeMem/ReallocMem`) and the scalar dynamic-array managed-value baseline are in `ir_codegen.inc` (pointer-sized slots, assignment retain/release, `SetLength`, zero-init growth, reclaim, conditional atomic refcounts under `--threadsafe`).

### Reality checks from review (do not assume away)

- **Managed strings remain opt-in at the Pascal surface.** The
  `{$define PXX_MANAGED_STRING}` path implements heap-backed strings, local
  cleanup, copy-on-write indexed writes, concatenation, coercions, and
  `SetLength`. Variant now supports managed-string assignment, copying,
  overwrite cleanup, local cleanup, and printing. String operators and the
  remaining ownership surfaces still need coverage.
- **No general linker.** The output path can't auto-pull a new RTL unit. Phase 1 must decide explicitly: Variant helpers as **compiler-emitted runtime routines** vs **linked RTL symbols**.
- **Allocator needs the target-neutral migration** in `docs/allocator-platform-design.md`: every target gets a syscall-free internal heap; hosted `mmap`/release/resize and ESP32 RTOS facilities stay optional hooks.

---

## Runtime prerequisites already on the active roadmap

Nil Python reuses managed-runtime work already needed by Pascal rather than growing a
Python-specific ownership layer. These are **Pascal milestones, not extra Nil Python costs**.
The scalar Variant and its first managed-string ownership slice are implemented.

1. Centralize the target-neutral allocator contract; add the syscall-free static-arena profile. Linux `mmap` stays an optional region hook; ESP32 bare-metal/RTOS use the same allocation contract.
2. Implement managed `AnsiString`: pointer slot, refcount, capacity, copy-on-write, one trailing `#0` for direct `PChar` compat.
3. Add shared managed-value init / overwrite / finalization / temp cleanup — covering normal scope exit, early `Exit`, exception unwinding, globals, record fields, class fields, parameters, results.
4. Complete dynamic arrays after those helpers: scope-exit release, params/results, managed elements, capacity-aware resize. The scalar baseline already works.

---

## Phasing

### Phase 1 — `tyVariant` (the reusable primitive) + `TAnyBox` stub

Build Variant first because it is **language-agnostic** (Object Pascal has `Variant`):
develop and test through the *existing Pascal frontend*, low-risk, before any new frontend
exists. Pascal and Nil Python both consume it. ("Don't invent it for Python alone.")

`tyVariant` = inline value type, fixed ~16 bytes: tag (`VType`) + 8-byte payload. Closed
scalar set: int / int64 / float / bool / char / managed string. String payloads
use the managed `AnsiString` heap reference directly.

Thin compiler layer over a fat library:
- `compiler/defs.inc`: add `tyVariant` type kind; `vt*` tag constants (incl. `vtEmpty`, reserved `vtObject`).
- `compiler/symtab.inc`: `TypeSize(tyVariant)` = 16; aggregate/value predicates.
- Lowering (`ir.inc`/`ir_codegen.inc`): route Variant assignment/operators/conversions to runtime helpers — `_VarFromInt(@v,x)`, `_VarFromStr(@v,s)`, `_VarAdd(@res,@a,@b)`, `_VarToInt(@v)`, `_VarClear(@v)`. Prefer a small shared managed-value lowering path over Variant-only special cases. **Decide helper delivery: compiler-emitted routines vs linked RTL symbols** (no general linker today).
- `lib/rtl/variants.pas` (new): tag switches, arithmetic, comparison, conversion — library, using existing operator-overload machinery where natural. Binary ops on two Variants = fixed `switch(VType)` double dispatch inside `_VarAdd` (closed set).
- **`TAnyBox` stub** (`lib/rtl/anybox.pas`): declare the `vtObject` tier (Variant payload = pointer to a boxed class/record) — *declared, not implemented*. The seam where Variant later composes with class-boxing without a redesign.

**Variant lifetime (`_VarClear`) — codegen contract.** A `tyVariant` holding a heap string
leaks if the stack frame is just abandoned. `ir_codegen.inc` must emit managed-value cleanup
shared by strings/arrays/Variants:
1. On entry, init each local `tyVariant` slot (tag = `vtEmpty`).
2. On rebind, if the current tag holds a heap ref, emit `_VarClear(@v)` *before* writing the new payload.
3. On every exit path (return / `Exit` / end / exception unwind), inject hidden `_VarClear(@v)` for each local `tyVariant`.
4. Same ownership accounting for expression temporaries, parameters, results, globals, records, container elements. Local-epilogue cleanup alone is **not** enough.

Test through Pascal, two steps:
- scalar Variant first: assign-across-types, arithmetic, comparison, conversion, temp cleanup.
- string Variant after managed `AnsiString`: `var v: Variant; v := 'hi'; writeln(v + ' world');`, overwrite cleanup, exits, exception paths.

### Phase 2 — Nil Python core frontend (the milestone)

Mirror the BASIC frontend file pattern. New files:

- `compiler/pylexer.inc` — **indentation-aware lexer**. The one genuinely new mechanism:
  - Track an indent stack; emit synthetic `INDENT`/`DEDENT` tokens (Python's algorithm, ~60 lines).
  - **Parenthesis-depth suspension**: maintain `parenDepth`; `(`/`[`/`{` increment, `)`/`]`/`}` decrement. Emit `INDENT`/`DEDENT` **only at `parenDepth = 0`** (multi-line literals/args format freely).
  - **Forbid mixing tabs and spaces** in one file — clean compiler error, no silent layout drift.
  - `:` block headers, newline = statement separator, `#` comments.
- `compiler/pyparser.inc` — `ParsePyProgram`; builds shared AST nodes; **reuses `ParseExpr`** (`parser.inc:2546`) as an *implementation strategy* (not the dialect grammar). Statements: `def`, `return`, `if/elif/else`, `while`, `for … in range(...)`, assignment, `print`/expression-statement, `pass`.
  - **Expression token normalization**: define the accepted operator table and map into the Pascal expression parser where semantics match (`==`, `!=`, `%`, boolean operators, chosen `//` policy). Reject unsupported Python operators clearly.
- **Local type inference — two-pass unification** (a slot's stack size/layout is fixed at compile time; a var can't be 4-byte `Integer` on line 2 and 16-byte `tyVariant` on line 10):
  - *Pass 1 — collect*: traverse the function body, record every local assignment, build a type-constraint graph.
  - *Pass 2 — resolve & retroactive promotion*: resolve constraints. Numeric widening (e.g. `Integer`+`Int64` → `Int64`) keeps the slot unboxed. Incompatible rebinds across control paths → **retroactively promote the var's declared type to `tyVariant` at function-scope entry**; non-scalar conflict → error ("annotate the type / too dynamic").
- **Function signatures explicit in v1**: require parameter and result annotations (local inference does not fix the ABI for `def fib(n)`, recursion, or calls-before-definition). Locals stay inferred. Whole-module signature solving is later, optional.
- Iterators: special-case `range()` (and later list iteration) into plain counter loops — **zero per-iteration overhead**; reserve a `MoveNext`/`Current` protocol over `IR_VIRTUAL_CALL` for general iterables only when added later.

Dispatch wiring — `compiler/compiler.pas:134-205`: add `.npy` detection, then
`PyLexAll; ParsePyProgram` in the handoff block that currently branches `isBasic`/`isC`.

**v1 surface (Core only):** `def`, control flow above, int/float/str/bool, arithmetic/compare,
`print`, functions, local inference. Proves the frontend end-to-end on the static path. No
containers, no classes yet.

### Phase 3 — Containers (libraries, not compiler hardcode)

`list`, `tuple`, `dict` — **library-first** (explicit preference, especially for Python): RTL
units over the target-neutral allocator and **completed managed dynamic arrays** (Prereq 4;
the provisional scalar-only array is not sufficient for `List[String]`/`List[Variant]`).
`dict` needs a new RTL hash table. `for x in <container>` uses the enumerator protocol. Add
only minimal parser sugar (`[]`, `{}`, indexing) — semantics live in RTL.

**Static parameterization with Variant escape**: `[1,2,3]` infers `List[Integer]` from the
unified element type; mixed `[1,"hello"]` promotes to `List[Variant]`. `x.append(val)` is
type-checked — `List[Integer].append("s")` is a compile-time error, pushing the dev to
declare `x: List[Variant]` if dynamic behavior is truly wanted.

**Tuple unpacking** (`a, b = …`) lands here, unless a smaller static multi-result ABI is
deliberately introduced earlier.

### Phase 4 — Classes = Pascal-class emulation

Map `class` / `self` / methods directly onto the existing Pascal class + VMT machinery
(`IR_VIRTUAL_CALL`). `__init__` → constructor, `self` → implicit `Self`. Accept dialect
quirks. No metaclasses, no runtime class mutation.

---

## Deferred costs (tracked, not v1)

- Heap-per-scalar if boxing with classes → avoided in tier 1 by Variant being a value type. Future opt: tagged-pointer fixnums.
- Boxes-holding-boxes cycles → the GC question, deferred. Closed-world + single-typed-default keeps this rare.

### BigInt is library-backed late polish

Python-style integers conceptually grow when an operation overflows the current
machine representation. Do not build arbitrary-precision arithmetic into the
compiler backend or penalize the ordinary integer path prematurely.

The eventual shape is:

- Keep native `Integer` / `Int64` arithmetic while values fit.
- Put arbitrary-precision arithmetic, shifts, formatting, and storage in an RTL
  BigInt library.
- Add an optional pointer payload tag such as `VT_BIGINT` to `Variant`; manage
  it like `VT_STRING`.
- Promote on overflow, oversized literals, or operations whose result no
  longer fits the native representation. Even trivial addition can carry, so
  this requires runtime overflow checks where Python-integer semantics are
  requested.
- Consider fixed-width `Int128` or wider intermediate fast paths only after
  profiling justifies them.

This is intentionally one of the last compatibility layers. It does not block
the current Nil Python core, containers, modules, SQLite, or async groundwork.

---

## Critical files

New:
- `compiler/pylexer.inc`, `compiler/pyparser.inc` (Phase 2)
- Variant runtime helpers — compiler-emitted routines *or* `lib/rtl/variants.pas` / `lib/rtl/anybox.pas` with an explicit inclusion strategy (Phase 1)
- `lib/rtl/` container units (Phase 3)
- `docs/nil-python.md` — dialect spec: grammar, accepted subset, operator table, quirks, the inference/promotion rule, the "compiler says no" boundary.
- `test/test_nil_python_core.npy` and friends.

Modified:
- `compiler/defs.inc` — `tyVariant` kind + `vt*` tags.
- `compiler/symtab.inc` — `TypeSize`/predicates for `tyVariant`.
- `compiler/ir.inc` / `compiler/ir_codegen.inc` — Variant lowering to runtime helpers; managed-value `_VarClear` cleanup; scalar-Variant fallback at the unify site.
- `compiler/compiler.pas` — `.npy` dispatch (`:134-205`).
- `Makefile` — build/run the new tests.

---

## Verification

- **Phase 1 (Variant via Pascal):** `test/test_variant.pas` — assign-across-types, arithmetic, comparison, temp cleanup, `VarClear` on reassign; build via the Pascal path, run, check output. Add string-payload coverage after managed `AnsiString`. Confirms the primitive before any frontend depends on it.
- **Phase 2 (core):** compile `test/test_nil_python_core.npy` (fib, loops, functions, inference). Run the binary, diff stdout. Negative test: deliberate unify-fail → clean `tyVariant` promotion *or* clear compiler error.
- **Indentation lexer:** nested blocks, blank lines, comments, mixed dedents, multi-line literals inside `()/[]/{}`, and a tab/space-mix error case — verify `INDENT`/`DEDENT` pairing and suspension.
- Wire all into the `Makefile` self-test target so regressions surface every build.
- Phases 3-4 gated behind their own tests (container ops + static-param error; a small class with method dispatch).

---

## Non-goals (explicit)

`eval`/`exec`, runtime self-modification, open dynamic typing, duck-typed attribute access on
unknown types, metaclasses, decorators (maybe later as sugar), generators (later), GC for
reference cycles. Nil Python is a pleasant *compiled* language, not a Python runtime.

---

## Getting started — first concrete steps

Ordered, each independently testable:

1. **Decide Variant helper delivery** (compiler-emitted vs linked RTL) — unblocks all of Phase 1. One-paragraph decision recorded in `docs/nil-python.md`.
2. **Add `tyVariant`** to `compiler/defs.inc` + `vt*` tags (incl. `vtEmpty`, reserved `vtObject`); `TypeSize`/predicates in `compiler/symtab.inc`.
3. **Scalar Variant lowering + `_VarClear` codegen** in `ir.inc`/`ir_codegen.inc`; `lib/rtl/variants.pas` scalar ops; `lib/rtl/anybox.pas` stub. Land `test/test_variant.pas` (scalar) green.
4. **Indentation lexer** `compiler/pylexer.inc` (indent stack + paren-depth suspension + tab/space guard); standalone token-dump test.
5. **`compiler/pyparser.inc`** core statements + explicit signatures + two-pass unification; `.npy` dispatch in `compiler.pas`. Land `test/test_nil_python_core.npy` green.
6. Then: managed `AnsiString` (Prereq 2-3) → string Variant → containers (Phase 3) → classes (Phase 4).

Defer until their phase: managed `AnsiString`, container RTL/hash table, classes.
