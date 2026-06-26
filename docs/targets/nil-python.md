---
title: Nil Python
order: 63
---

# Nil Python (`.npy`)

Nil Python is an experimental, statically compiled Python-shaped frontend for the PXX compiler. It compiles `.npy` source files directly to native machine code through the shared AST and backend, achieving high performance without the overhead of a Python interpreter or runtime.

> [!NOTE]
> Nil Python is not a full Python implementation. It is a compiled dialect designed for close interop with Pascal and C. The `.py` extension is intentionally unsupported to prevent confusion with standard Python.

---

## Language Surface

Nil Python uses standard Python indentation syntax to define blocks. It requires explicit type annotations on function parameters and return types, while local variables are automatically inferred.

### Supported Statements

```python
# A simple function with type annotations
def calculate_factorial(n: int) -> int:
    result = 1
    for i in range(1, n + 1):
        result = result * i
    return result

# Control flow
if x > 10:
    print("Greater")
elif x == 10:
    print("Equal")
else:
    print("Lesser")

# Loops
while active:
    poll_events()
```

### Syntax Rules
- **Indentation**: Indentation defines blocks. Mixing tabs and spaces in the same file is forbidden and triggers a compile error.
- **Parenthesis Suspension**: Indentation rules are suspended inside parentheses (`()`, `[]`, `{}`), allowing clean multi-line function calls or literal declarations.
- **Explicit Signatures**: Parameter and return annotations are mandatory for functions. This maintains a fixed native ABI for recursion and cross-calling before a function body has been fully parsed.

---

## Type Inference & The Variant Escape Valve

Nil Python is statically typed under the hood. The compiler performs local type inference across two passes to resolve the type of every variable:

1. **Numeric Widening**: Assigning compatible numeric types keeps the variable unboxed and fast (e.g., assigning an `int` and later a `float` to the same variable resolves the slot to a standard 64-bit float).
2. **Variant Promotion**: If a variable is rebound to incompatible types across different control paths (e.g., an integer on one path, and a string on another), the compiler **retroactively promotes** the variable to a 16-byte `tyVariant` stack slot at the entry of the function.
3. **Static Rejection**: Incompatible assignments involving records, classes, or dynamic arrays cannot be promoted to Variant and are rejected at compile time with a clear diagnostic.

---

## Wrapper-Free C Interop

The most powerful feature of Nil Python is its ability to import C headers directly and call shared-library symbols natively without any handwritten wrapper code.

```python
import sqlite3

# Call sqlite3 C functions directly
db = sqlite3_open("/tmp/users.db")
sqlite3_exec(db, "CREATE TABLE users(id INT, name TEXT);", 0, 0, 0)
```

### 1. Autotyping (Return-Lifting)
C APIs frequently return status codes and pass output handles via pointer-to-pointer parameters (e.g., `int sqlite3_open(const char*, sqlite3**)`). 

Since Nil Python has no pointer or address-of (`&`) operators, the compiler automatically detects trailing double-pointer out-parameters (`T**`) when reading the C header. It return-lifts the parameter:
- The compiler allocates a hidden local pointer on the stack.
- It passes the address of this pointer to the C function.
- It returns the resulting handle directly as the Python-level return value (e.g., `db = sqlite3_open(path)`).

### 2. Automatic String Marshalling
- **Input**: Python strings passed to C `const char*` parameters are automatically marshalled as NUL-terminated C strings.
- **Output**: C functions returning `char*` or `const char*` have their returned text copied automatically into managed, reference-counted PXX strings. The underlying C memory remains owned by the C library.

### 3. Macro Constant Mapping
Preprocessor integer `#define` macros in the C header (such as `SQLITE_ROW` or `SQLITE_OK`) are parsed and made available directly as ordinary constants in Nil Python.
