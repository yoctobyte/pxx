# Nil Python Dialect

Nil Python is the statically compiled `.npy` frontend for PXX. It uses
Python-shaped syntax while compiling through the shared AST and native x86-64
backend. A `.py` extension is intentionally unsupported: Nil Python is a small
compiled dialect, not a Python runtime.

## Core Statements

The v1 frontend accepts:

```text
def name(param: type, ...) -> type:
    statements
return expression
if expression:
    statements
elif expression:
    statements
else:
    statements
while expression:
    statements
for name in range(...):
    statements
name = expression
print(expression, ...)
expression
pass
```

Indentation defines blocks. Blank lines and `#` comments are accepted.

Function parameter and result annotations are mandatory. Supported annotation
spellings are `int`, `float`, `bool`, and `str`. Locals remain inferred.
Explicit signatures keep the native ABI fixed for recursion and calls before a
body has been compiled.

## Type Inference

Nil Python resolves every assignment to a local before allocating its slot.
Numeric widening keeps compatible values unboxed. For example, an integer and
a floating-point assignment resolve to a floating-point slot.

When incompatible assignments remain inside the closed scalar set, the slot is
promoted retroactively to a 16-byte `tyVariant` value:

```text
int, int64, float, bool, char
```

`tyVariant` is a tagged scalar escape hatch, not an open dynamic top type.
Assignment and `print` dispatch for scalar Variants are implemented. Do not
rely on Variant arithmetic until its backend support lands.

String payloads are not supported yet because managed `AnsiString` is still
pending. Rebinding a scalar slot to a string produces:

```text
string-typed Variant pending managed AnsiString
```

Records, classes, arrays, and containers do not promote to Variant. Dynamic
conflicts outside the scalar set are rejected with an `annotate the type / too
dynamic` diagnostic.

## Operators

| Nil Python | Meaning |
| --- | --- |
| `+`, `-`, `*` | arithmetic |
| `//` | integer division |
| `%` | integer remainder |
| `==`, `!=`, `<`, `<=`, `>`, `>=` | comparison |
| `and`, `or`, `not` | boolean operators |

`/` is rejected in v1. Use `//` for integer division.

## Current Limits

- `range(stop)` and `range(start, stop)` lower to a native counter loop.
- A `range` step is accepted only when it is exactly `1`.
- Functions currently support at most four parameters in generated code.
- Containers, classes, dynamic attributes, decorators, generators, `eval`, and
  `exec` are outside the v1 frontend.
- Variant arithmetic is not part of the documented surface yet.
- String-capable Variant waits for managed `AnsiString`.

## Regression Tests

Run the focused frontend suite with:

```sh
make test-nilpy
```

The suite compiles and runs the core and scalar-Variant programs, then verifies
the `/` and string-Variant rejection paths.
