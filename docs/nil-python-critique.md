# Nil Python (No/Not Python): Frontend Design & Robustness Critique

An engineering critique of the "Nil Python" compiler roadmap, highlighting latent syntactic ambiguities, runtime memory management trade-offs, and compiler-level unification rules that must be resolved to ensure a production-grade, highly optimized compiled frontend.

---

## 1. Local Type Inference: The Retrospective Unification Rule

The roadmap specifies:
> *"Every var starts statically typed (inferred from first binding). The checker unifies types across rebinds: unify fails ... promote slot to `tyVariant`."*

### The Challenge
A variable slot's physical size and layout in the CPU stack frame must be fixed and immutable at compile time. A local variable `x` cannot exist as a 4-byte `Integer` on line 2, and dynamically transform into a 16-byte `tyVariant` on line 10.

Consider this case:
```python
x = 1             # Binding A (inferred as Integer)
if condition:
    x = "hello"   # Binding B (inferred as String) -> Unification Fails!
```

### The Unification Specification
To resolve this, the **Nil Python** compiler must implement a **two-pass unification type-checker** over the AST before lowering:
1. **Pass 1 (Collection & Constraint Formulation)**: Traverses the function body, recording every assignment to local variables and building a type constraint graph.
2. **Pass 2 (Resolution & Retroactive Promotion)**: Resolves the constraint graph. If any local variable variable is rebound to incompatible types across different control paths, the compiler must **retroactively promote the variable's declaration type to `tyVariant`** at the very beginning of the function scope. 
3. If unification succeeds via numeric widening (e.g. `Integer` and `Int64` unified to `Int64`), the variable remains unboxed and optimized.

---

## 2. Variant Lifetime Management (`_VarClear`)

A `tyVariant` is an inline 16-byte value type, but it can hold a heap reference (such as a dynamic string, dynamic array, or class reference payload).

### The Challenge (Memory Leaks)
In Object Pascal, local stack variables of primitive types are simply abandoned when the stack pointer is restored upon function exit. However, if a `tyVariant` holds a heap-allocated string, simply discarding the stack frame will cause a silent **heap memory leak**.

### The Specification
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

---

## 3. Indentation Lexer & Parenthesis Depth Suspension

The `pylexer.inc` is tasked with tracking indentation changes and generating synthetic `INDENT`/`DEDENT` tokens to replace block braces.

### The Challenge
In standard Python, indentation rules are strictly **suspended** when inside open parentheses `()`, brackets `[]`, or braces `{}`. This allows developers to format multi-line list literals or function arguments cleanly:

```python
my_list = [
    1,
    2,
    3
] # The dedent here must NOT emit a DEDENT token!
```

### The Specification
1. **Parenthesis Depth Counter**: The `pylexer.inc` must maintain a `parenDepth` integer. Any encounter of `(`, `[`, `{` increments the counter; `)`, `]`, `}` decrements it.
2. **Suspension Rule**: Synthetic `INDENT` and `DEDENT` tokens must **only** be emitted when the line change occurs at `parenDepth = 0`.
3. **Tab Error Prevention**: The lexer must explicitly forbid mixing tabs and spaces in the same file, raising a clean compiler error to avoid silent blocks layout mismatches.

---

## 4. Container Types: Static Parameterization vs. Dynamic Lists

Python lists `[1, 2, 3]` are dynamically typed arrays under the hood.

### The Challenge
If `x = [1, 2, 3]` is compiled, we must decide if it maps to a statically typed list (`List[int]`) or a dynamic list of variants (`List[Variant]`).
* If always dynamic: We pay a massive boxing and dereferencing penalty for standard loops, breaking our "ultra-fast native binary" focus.
* If always static: Appending a different type later (`x.append("hello")`) will trigger a compiler error.

### The Specification
To maintain PXX/Nil Python's high-performance compiled philosophy, we implement **Static Parameterization with Variant Escape**:
1. Literals `[1, 2, 3]` are inferred as **statically typed** (`List[Integer]`) based on the unified type of their elements.
2. If the literal elements are incompatible (e.g. `[1, "hello"]`), the container is promoted to `List[Variant]`.
3. Operations like `x.append(val)` are type-checked. If `x` is `List[Integer]` and `val` is a string, the compiler raises a type mismatch error *at compile time*, encouraging the developer to declare `x: List[Variant]` explicitly if dynamic behavior is truly intended.

---
