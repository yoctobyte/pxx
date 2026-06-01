# Plan: "Nil Python" (No/Not Python) frontend for frankonpiler

## Context

The compiler ships a BASIC demo frontend, but BASIC is a poor showcase: verbose,
dated grammar. We want a **Python-shaped** frontend instead — short, readable code,
clean grammar — without paying for CPython's dynamic-everything machine. Full Python
is non-goals (no `eval`, no self-modification, no open runtime type universe). Like MicroPython/RPython/Boo/Genie/Nim, this is a *somewhat-compatible dialect*, named
**"Nil Python"** (No/Not Python).

Core design decision (settled with the user): **statically typed, with local type
inference and a top-type escape valve.** Every var starts statically typed (inferred
from first binding). The checker unifies types across rebinds:

- common static type exists (numeric widening only — *no* JS-style coercion) → stay unboxed.
- unify fails but both sides fit a fixed scalar set → **promote slot to `tyVariant`**.
- unify fails and a side doesn't fit (arbitrary class/record) → **compiler says no** (clear error).

"Proper code is single-typed; Variant is the escape valve inference reaches for, not the
default." 95% of code stays unboxed and compiles to fast native via the existing IR.

### Why this is cheap to build

A frontend here is only **lexer + parser that build the shared AST**, then call
`CompileAST()`. BASIC is ~620 lines and even borrows Pascal's `ParseExpr`. The whole
backend — IR, regalloc, x86-64 emission, ELF — is shared and free. The cost is *semantics*,
handled by the phasing below.

### Reusable machinery already present (verified)

- Frontend dispatch by file extension — `compiler/compiler.pas:134` (`isC`/`isBasic`), parse handoff `:182`.
- Shared AST node kinds — `compiler/defs.inc:62-112`; build via the same nodes BASIC uses.
- `CompileAST()` handoff — `compiler/ir_codegen.inc:1989` (`IRReset; IRLowerAST; IRVerify; IREmitMachineCode`).
- **`tySet` precedent** for a value-type-with-special-ops — `compiler/defs.inc:299`, `IR_SET_LIT/COPY/BINOP/CMP` `:154-163`. `tyVariant` follows this pattern but leaner (likely **zero new IR opcodes** — just `IR_CALL` to RTL helpers).
- **Operator overloading already works** — `ParseOperatorDef` `compiler/parser.inc:558` (`operator < (a,b: TMyType): Boolean`). Variant/box behavior lives in RTL, not the compiler.
- **Virtual dispatch (VMT)** — `IR_VIRTUAL_CALL`; classes map straight onto this.
- Type sizing — `TypeSize` `compiler/symtab.inc:683`.
- Heap (`GetMem/FreeMem/ReallocMem`), heap-backed length-prefixed strings, dyn arrays — all in `ir_codegen.inc` + `lib/rtl/`.

### Known deferred costs (phase 2+, not v1)

- Heap-per-scalar if boxing with classes → avoided in tier 1 by making Variant a **value type** (inline ~16B). Future opt: tagged-pointer fixnums.
- Binary ops on two Variants need **double dispatch** → a fixed `switch(VType)` inside `_VarAdd` (closed set). All in RTL.
- Variant holding a string must manage that string's lifetime (`VarClear` before overwrite); ships with copy semantics, tightens when string refcounting lands. **Does not hard-block.**
- Boxes-holding-boxes cycles → the GC question, deferred. Closed-world + single-typed-default keeps this rare.

---

## Phasing (user-approved order)

### Phase 1 — `tyVariant` (the reusable primitive) + `TAnyBox` stub

Build Variant first because it is **language-agnostic** (Object Pascal has `Variant`):
develop and test it through the *existing Pascal frontend*, low-risk, before any new
frontend exists. Pascal and Nil Python both consume it. ("Don't invent it for Python alone.")

`tyVariant` = inline value type, fixed ~16 bytes: tag (`VType`) + 8-byte payload. Closed
scalar set: int / int64 / float / bool / char / string (string payload = heap ref).

Thin compiler layer over a fat library:
- `compiler/defs.inc`: add `tyVariant` type kind; `vt*` tag constants.
- `compiler/symtab.inc`: `TypeSize(tyVariant)` = 16; aggregate/value predicates.
- Lowering (`ir.inc`/`ir_codegen.inc`): route Variant assignment/operators/conversions to
  RTL helper calls via `IR_CALL` — `_VarFromInt(@v,x)`, `_VarFromStr(@v,s)`,
  `_VarAdd(@res,@a,@b)`, `_VarToInt(@v)`, `_VarClear(@v)`. Prefer **no new IR opcodes**.
- `lib/rtl/variants.pas` (new): the tag switches, arithmetic, comparison, conversion — all
  library, using existing operator-overload machinery where natural.
- **`TAnyBox` stub** (`lib/rtl/anybox.pas`): declare the `vtObject` tier (Variant payload =
  pointer to a boxed class/record) — *declared, not implemented*. This is the seam where
  Variant later composes with class-boxing without a redesign.

Test via Pascal: `var v: Variant; v := 5; v := 'hi'; writeln(v + ' world');` etc.

### Phase 2 — Nil Python core frontend (the milestone)

Mirror the BASIC frontend file pattern. New files:
- `compiler/pylexer.inc` — **indentation-aware lexer**. The one genuinely new mechanism:
  track an indent stack, emit synthetic `INDENT`/`DEDENT` tokens (Python's own algorithm,
  ~60 lines). Otherwise tokens feed the existing pipeline. Handle `:` block headers, newlines
  as statement separators, comments (`#`).
- `compiler/pyparser.inc` — `ParsePyProgram`; builds shared AST nodes; **reuses `ParseExpr`**
  (`parser.inc:2546`) for expressions like BASIC does. Statements: `def`, `return`,
  `if/elif/else`, `while`, `for … in range(...)`, assignment (incl. tuple unpack `a, b = …`),
  `print`/expression-statement, `pass`.
- **Local type inference** in the Py frontend: first binding of a name resolves its static
  type from the RHS expression type (reuse existing type resolution); rebind unifies; on
  unify-fail apply the top-type rule (→ `tyVariant` since Phase 1 shipped it, else error with
  a clear "annotate the type / too dynamic" message).
- Iterators done right: special-case `range()` and (later) list iteration into plain counter
  loops — **zero per-iteration overhead**; reserve a `MoveNext`/`Current` protocol over
  `IR_VIRTUAL_CALL` for general iterables only when added later.

Dispatch wiring — `compiler/compiler.pas:134-205`: add `.tpy` detection (primary; optionally
also accept `.py` for editor tooling), then `PyLexAll; ParsePyProgram` in the handoff block
that currently branches `isBasic`/`isC`.

v1 surface (Core only): `def`, control flow above, int/float/str/bool, arithmetic/compare,
`print`, functions, inference. Proves the frontend end-to-end on the static path. No
containers, no classes yet.

### Phase 3 — Containers (libraries, not compiler hardcode)

`list`, `tuple`, `dict`. **Library-first** (explicit user preference, especially for Python):
implement as RTL units over existing heap + dyn arrays; `dict` needs a new RTL hash table.
`for x in <container>` uses the enumerator protocol. Add only minimal parser sugar (`[]`,
`{}`, indexing) — semantics live in RTL.

### Phase 4 — Classes = Pascal-class emulation

Map `class` / `self` / methods directly onto the existing Pascal class + VMT machinery
(`IR_VIRTUAL_CALL`). Accept dialect quirks/limitations — "plenty power and totally doable."
`__init__` → constructor, `self` → implicit `Self`. No metaclasses / no runtime class mutation.

---

## Critical files

New:
- `compiler/pylexer.inc`, `compiler/pyparser.inc` (Phase 2)
- `lib/rtl/variants.pas`, `lib/rtl/anybox.pas` (Phase 1)
- `lib/rtl/` container units (Phase 3)
- `docs/typed-python.md` — dialect spec: grammar, accepted subset, quirks, the inference/promotion rule, the "compiler says no" boundary.
- `test/test_typed_python_core.tpy` and friends.

Modified:
- `compiler/defs.inc` — `tyVariant` kind + `vt*` tags.
- `compiler/symtab.inc` — `TypeSize`/predicates for `tyVariant`.
- `compiler/ir.inc` / `compiler/ir_codegen.inc` — Variant lowering to RTL `IR_CALL`s; top-type fallback at the unify site.
- `compiler/compiler.pas` — `.tpy` dispatch (`:134-205`).
- `Makefile` — build/run the new tests.

---

## Verification

- **Phase 1 (Variant via Pascal):** a `test/test_variant.pas` exercising assign-across-types,
  arithmetic, comparison, string payload, `VarClear` on reassign; build with the existing
  Pascal path, run, check output. Confirms the primitive before any frontend depends on it.
- **Phase 2 (core):** compile `test/test_typed_python_core.tpy` (fib, loops, functions,
  inference). Run the produced binary, diff stdout against expected. Add a negative test:
  a deliberate unify-fail → expect either a clean `tyVariant` promotion or a clear compiler
  error (per the rule).
- **Indentation lexer:** targeted test with nested blocks, blank lines, comments, mixed
  dedents — verify `INDENT`/`DEDENT` pairing.
- Wire all into the `Makefile` self-test target so regressions surface on every build.
- Phases 3-4 gated behind their own tests (container ops; a small class with method dispatch).

## Non-goals (explicit)

`eval`/`exec`, runtime self-modification, open dynamic typing, duck-typed attribute access on
unknown types, metaclasses, decorators (maybe later as sugar), generators (later), GC for
reference cycles. Nil Python is a pleasant *compiled* language, not a Python runtime.

---

## Critique & Robustness Specifications (Added 2026-06-01)

### 1. Local Type Inference: The Retrospective Unification Rule
A variable slot's physical size and layout in the CPU stack frame must be fixed and immutable at compile time. A local variable `x` cannot exist as a 4-byte `Integer` on line 2, and dynamically transform into a 16-byte `tyVariant` on line 10.

Consider this case:
```python
x = 1             # Binding A (inferred as Integer)
if condition:
    x = "hello"   # Binding B (inferred as String) -> Unification Fails!
```

To resolve this, the **Nil Python** compiler must implement a **two-pass unification type-checker** over the AST before lowering:
* **Pass 1 (Collection & Constraint Formulation)**: Traverses the function body, recording every assignment to local variables and building a type constraint graph.
* **Pass 2 (Resolution & Retroactive Promotion)**: Resolves the constraint graph. If any local variable variable is rebound to incompatible types across different control paths, the compiler must **retroactively promote the variable's declaration type to `tyVariant`** at the very beginning of the function scope. 
* If unification succeeds via numeric widening (e.g. `Integer` and `Int64` unified to `Int64`), the variable remains unboxed and optimized.

### 2. Variant Lifetime Management (`_VarClear`)
In Object Pascal, local stack variables of primitive types are simply abandoned when the stack pointer is restored upon function exit. However, if a `tyVariant` holds a heap-allocated string, simply discarding the stack frame will cause a silent **heap memory leak**.

Our code generator (`ir_codegen.inc`) must be extended to support automatic scope cleanup:
1. When entering a function that allocates a local `tyVariant` variable, the stack frame is initialized (tag set to `vtEmpty`).
2. When the variable is rebound, if the tag holds a heap reference, the compiler must emit a call to `_VarClear(@v)` *before* writing the new payload.
3. Upon function exit (return, exit, or end), the compiler must inject a hidden `_VarClear(@v)` call for every local `tyVariant` variable allocated in the stack frame.

```pascal
{ Emitted function epilogue pseudo-code }
begin
  _VarClear(@local_var_x);
  _VarClear(@local_var_y);
  { Restore stack pointer and return }
end;
```

### 3. Indentation Lexer & Parenthesis Depth Suspension
In standard Python, indentation rules are strictly **suspended** when inside open parentheses `()`, brackets `[]`, or braces `{}`. This allows developers to format multi-line list literals or function arguments cleanly.

1. **Parenthesis Depth Counter**: The `pylexer.inc` must maintain a `parenDepth` integer. Any encounter of `(`, `[`, `{` increments the counter; `)`, `]`, `}` decrements it.
2. **Suspension Rule**: Synthetic `INDENT` and `DEDENT` tokens must **only** be emitted when the line change occurs at `parenDepth = 0`.
3. **Tab Error Prevention**: The lexer must explicitly forbid mixing tabs and spaces in the same file, raising a clean compiler error to avoid silent blocks layout mismatches.

### 4. Container Types: Static Parameterization vs. Dynamic Lists
To maintain PXX/Nil Python's high-performance compiled philosophy, we implement **Static Parameterization with Variant Escape**:
1. Literals `[1, 2, 3]` are inferred as **statically typed** (`List[Integer]`) based on the unified type of their elements.
2. If the literal elements are incompatible (e.g. `[1, "hello"]`), the container is promoted to `List[Variant]`.
3. Operations like `x.append(val)` are type-checked. If `x` is `List[Integer]` and `val` is a string, the compiler raises a type mismatch error *at compile time*, encouraging the developer to declare `x: List[Variant]` explicitly if dynamic behavior is truly intended.
