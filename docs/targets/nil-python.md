---
title: Nil Python
order: 63
---

# Nil Python (`.npy`)

Nil Python is a statically compiled Python-shaped frontend for the PXX compiler. It compiles `.npy` source files directly to native machine code through the shared AST and backend, achieving high performance without the overhead of a Python interpreter or runtime.

It is a **mainline frontend**, a peer of Pascal and C rather than a research path: it has its own test gate (`test-nilpy`), which must be green — along with a byte-identical self-host and the cross-target builds — before any change lands. BASIC, Rust and Zig are the experimental frontends; Nil Python began there and no longer is.

> [!NOTE]
> Nil Python is not a full Python implementation. Source files can use either the `.npy` extension or plain `.py` — both compile through the same frontend; PXX does not require CPython-standard syntax, so a `.py` file that leans on dynamic-typing features CPython allows may not compile as-is.

## What it is aiming at

The frontend began as a Python-*shaped* dialect — the point was to prove that a
grammar nothing like Pascal's could reach the same backend. That is no longer
the goal it is measured against. Where a construct is implemented, the target
is **CPython's observable behaviour**, and divergences from it are filed as
bugs rather than accepted as dialect differences. Nil Python is a from-scratch
compiler that targets CPython compatibility; it is not derived from CPython's
implementation, and it is not an interpreter.

That is a harder target than Pascal or C, and the board shows it: Nil Python's
open queue peaked at 79 tickets against 30 for the C frontend and 20 for
Pascal's, and 77% of its tickets are bugs or regressions. A deep queue here
means the reference is exacting, not that the frontend is fragile — see
[ticket flow](https://pxxc.org/status/flow/) for the curves.

**What it will not do**, and this is a design boundary rather than a gap to
close: anything requiring a live interpreter. No `eval` of runtime-constructed
code, no monkeypatching a class after compilation, no duck typing resolved at
run time. Function parameters and return types need annotations; locals are
inferred. If a program's design depends on Python's dynamism, it belongs on
CPython.

### It hardens the rest of the compiler

Compiling Python-shaped code exercises the shared AST, IR and runtime along
paths that Pascal and C programs rarely reach — variants, dunder dispatch,
container semantics — and the defects it turns up are usually **not** in the
Nil Python frontend at all. They land in the shared layers, where fixing them
benefits every frontend. Over 100 tickets in the compiler-core lane reference
Nil Python work. It has been the cheapest bug-discovery route the project has:
no third-party test corpus had to be dragged into Pascal or C to find them.

---

## Language Surface

Nil Python uses standard Python indentation syntax to define blocks. Type
annotations on parameters and return types are **optional but recommended**: an
unannotated parameter becomes a dynamically-typed (variant) slot that accepts an
int, a float, a string or a list, while an annotated one compiles to a native
typed slot. Local variables are always inferred.

Annotate the **return type** in particular where the value matters. Inference
of an omitted return type is currently wrong for true division — `def half(x):
return x / 2` yields `2` rather than `2.5`, and with an annotated parameter it
yields the double's raw bit pattern as an integer. Writing `-> float` is a
complete workaround. This is a tracked defect, listed under
[known gotchas](#known-gotchas) below.

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
- **Signatures**: Annotations are optional. An annotated signature gives the
  function a fixed native ABI, which is what lets recursion and cross-calling
  resolve before a body has been fully parsed; an unannotated one is dynamic
  and slower.

---

## Type Inference & The Variant Escape Valve

Nil Python is statically typed under the hood. The compiler performs local type inference across two passes to resolve the type of every variable:

1. **Numeric Widening**: Assigning compatible numeric types keeps the variable unboxed and fast (e.g., assigning an `int` and later a `float` to the same variable resolves the slot to a standard 64-bit float).
2. **Variant Promotion**: If a variable is rebound to incompatible types across different control paths (e.g., an integer on one path, and a string on another), the compiler **retroactively promotes** the variable to a 16-byte `tyVariant` stack slot at the entry of the function.
3. **Promotion covers containers and objects too**: rebinding a list-valued or
   class-valued variable to an incompatible type promotes it to Variant the same
   way rather than being refused. (An earlier compiler rejected these at compile
   time; verified against the pinned compiler that it no longer does.)

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

---

## Classes

Multiple bases — `class C(A, B):` — are accepted, and methods from both bases
are callable on the subclass. Where two bases declare the same method the first
base wins, which is what C3 linearisation gives for a flat hierarchy. Calling a
base constructor explicitly as `B.__init__(self)` is refused, so a two-base
class cannot chain both initialisers; `super().__init__(...)` reaches the first
base only.

Dunder methods dispatch. Verified against the pinned compiler:
`__init__`, `__str__`, `__repr__`, `__eq__`, `__len__`, `__getitem__`,
`__call__`, `__enter__`/`__exit__` (so `with` works on your own classes), and
`__iter__`/`__next__` (so a class of your own is usable as the subject of a
`for` loop) all resolve to the method you defined.

One sharp edge in an iterator: `raise StopIteration` must be written
`raise StopIteration()`, because an exception class is not usable as a bare
value.

`super().method(args)` is recognized specifically as its own call
**statement** — most commonly `super().__init__(...)` chaining a parent
constructor — not as a general expression whose result you can use further
(`x = super().method()` or embedding it in a larger expression is not
supported):

```python
class Animal:
    def __init__(self, name: str) -> None:
        self.name = name


class Dog(Animal):
    def __init__(self, name: str) -> None:
        super().__init__(name)
```

`@property` and its matching `@x.setter` are supported on methods:

```python
class Box:
    def __init__(self, v: int) -> None:
        self._v = v

    @property
    def v(self) -> int:
        return self._v

    @v.setter
    def v(self, val: int) -> None:
        self._v = val
```

At module level, only `@dataclass` is accepted as a decorator — it generates
an `__init__` from the annotated fields:

```python
@dataclass
class Point:
    x: int
    y: int
```

`@staticmethod` works. `@classmethod` is refused with a diagnostic saying why:
its `cls` receiver is not modelled, and binding it to the declaring class would
be silently wrong in a subclass.

## Functions: defaults, `*args`, `**kwargs`, lambdas

Default parameter values, `*args` (collected as a list), and `**kwargs`
(collected as a dict) are supported on the callee side:

```python
def total(*args):
    s = 0
    for a in args:
        s = s + a
    return s

def opts(a, **kw):
    for k in kw:
        print(k, kw[k])
```

`lambda` is a real, compiled closure (not restricted to trivial expressions).
`yield` works and gives a genuinely lazy generator — a `for` loop over an
infinite generator that `break`s runs the body only as far as it consumed. A
generator *expression* like `(x for x in it)` is the exception: it is accepted
as sugar but desugars eagerly into a list, so its elements are all computed
before the loop starts.

## Control flow

`if`/`elif`/`else`, `while`, `for … in`, `break`/`continue`/`pass`, and
`try`/`except (A, B):`/`finally` (including multiple `except` clauses) all
work as expected, and so does `assert`. `with` calls `__enter__`/`__exit__` on
a class of your own (an earlier compiler treated it as scoping sugar only).

List/dict/set comprehensions, including nested and filtered (`if`) forms, are
supported and compile down to an imperative build:

```python
squares = [x * x for x in range(10) if x % 2 == 0]
```

Not present: `match`/`case` and `async`/`await`.

## f-strings

`f"{value!r}"`/`f"{value!s}"` conversions and a plain format spec are
supported. Triple-quoted f-strings are not.

## Standard-library surface

`import` resolves against a real backing Pascal unit for a growing list of
module names: `re`, `json`, `math`, `random`, `collections`, `configparser`,
`base64`, `pathlib`, `subprocess`, `time`, `typing`, `dataclasses`. `sys`, `os`,
`textwrap`, `select`, and `itertools` are recognized and partially supported
without a dedicated shim unit. `tkinter` has its own facade
(`lib/pcl/tkinter.pas`) for GUI programs. Not yet present: `socket`,
`threading`, `struct`, `enum`, `csv`, `pickle`, `logging`, `hashlib`, `uuid`,
`datetime`.

## Shims: standing in for a Python package

Some module names resolve to a unit PXX wrote itself, presenting a familiar
Python API over PXX's own code. These are **shims**, and they are deliberately
visible rather than hidden.

A shim lives under PXX's own name — `mimic_<module>` — never the upstream
package's. So no file in the tree carries a name it did not earn, and listing
the directory tells you exactly which packages are being stood in for:

```
lib/pcl/mimic_reportlab_pdfgen.pas          <- from reportlab.pdfgen import canvas
lib/pcl/mimic_reportlab_lib_pagesizes.pas   <- from reportlab.lib.pagesizes import A4
lib/pcl/mimic_tkinter_font.pas              <- import tkinter.font as tkfont
```

A dotted package name is flattened before lookup, which is why
`from reportlab.pdfgen import canvas` reaches `mimic_reportlab_pdfgen` with no
package-directory machinery involved.

### The mapping is a last resort

The `mimic_` substitution is consulted **only after every ordinary lookup has
failed**. A real unit of that name always wins — a sibling `.py`, a Pascal unit
such as `lib/rtl/re.pas`, a C header. It applies to Nil Python only; a Pascal
`uses` never reaches the shim table at all.

Not every Python-shaped facade is a shim, and the distinction is the filename.
`lib/pcl/tkinter.pas` is a real unit *named* `tkinter`, so `import tkinter`
resolves to it by ordinary lookup and no substitution happens. Only
`import tkinter.font` — which has no unit of its own — falls through to
`mimic_tkinter_font`.

### A build says what it substituted

Every substitution prints a line, because a program built on a subset should
say so:

```
$ ./pxx report.npy report
note: reportlab_lib_units -> mimic_reportlab_lib_units (shim, subset)
ok: report  [code=1179172B  data=31684B  bss=8332B  procs=1036]
```

**`(shim, subset)` is the important part.** A shim implements what PXX needs of
that API, not the package. Treat an unexercised call as unimplemented until you
have run it.

### `--no-shims`: turning the claim into a check

Passing `--no-shims` refuses the substitution outright — every import must
resolve to a real unit of that name or the build fails:

```
$ ./pxx --no-shims report.npy report
pascal26:1: error: import: no unit named reportlab_lib_units (--no-shims refuses the mimic_ substitution)
```

This is what makes "compiled without compatibility shims" a checked property
rather than a claim. Use it when you need to know that a binary contains no
stand-in code — for a dependency audit, or to find out how much of a program
actually rests on shimmed surface. It is not a hardening flag: a build that
passes `--no-shims` is not more correct, only more honest about what it used.

## `__file__`, `sys.executable`, and where data files live

A compiled Nil Python program has no source file at run time, so `__file__`
names the **executable**:

- for the **main module**, it is the binary's own absolute path;
- for an **imported module**, it is that binary's directory joined with the
  module's file name — a path that need not exist;
- `sys.executable` is the same binary. (Under CPython it is the interpreter,
  which is the same idea: the thing that is actually running.)

All three are absolute and independent of the current directory. The practical
consequence is the line every program that ships data files already has:

```python
here = os.path.dirname(os.path.abspath(__file__))   # the executable's directory
path = os.path.join(here, "data.json")
```

Under CPython that finds data next to your `.py` sources. In a compiled build it
finds data next to the **binary** — so that is where to put it. Copy the
executable somewhere else and `here` follows it, because the path is resolved
from the running program, not baked in at compile time.

Frozen Python does the same thing for the same reason: PyInstaller and cx_Freeze
also point `__file__` at the bundle rather than at sources that are no longer
there. If you have shipped a frozen app, this is the shape you already know.

Two things follow that are worth knowing before you meet them:

- `open(__file__)` in the main module **succeeds, and opens the executable** —
  a couple of megabytes of ELF, not Python source. In an imported module it
  fails, because that path is synthesized and no file is there.
- Code that keeps data beside its `.py` sources and reaches it through
  `__file__` needs the data moved next to the binary, or the path supplied
  some other way (an argument, an environment variable, a config file).

## Known gotchas

These are open, tracked issues — real-world `.py`/`.npy` programs can still
hit them:

- The inferred return type of a bare `return x / 2` is an integer: the value
  is truncated, or — with an annotated parameter — handed back as the double's
  raw bit pattern. Annotate the return type as `-> float`.
- Calling a method no class declares is a **compile error**, not a runtime
  `AttributeError`, so a program that catches `AttributeError` around a
  deliberately-missing attribute does not build.
- `super().method()` is a statement form only. Using it as an expression
  (`return super().hi()`) fails to compile, with a diagnostic that names
  neither the construct nor the right line. `Parent.method(self)` works and is
  the usable spelling.
- A keyword argument resolves against only one overload of an overload set —
  it can fail on a sibling overload that has the same parameter name.
- Object reclamation (reference counting) is disabled inside an imported
  `.py` module specifically — a module compiled as the main program does not
  have this restriction.
- ~~A `def`/`lambda` in a plain variable can silently do nothing or segfault
  when called.~~ ~~Missing methods segfault.~~ ~~`int("abc")` halts instead of
  raising a catchable `ValueError`.~~ ~~`"%d" % value` yields garbage.~~
  ~~`str()` of a tuple/list prints a pointer.~~ ~~`not some_object` is always
  `True`.~~ ~~`str.encode`/`bytes.decode` ignore the codec.~~ ~~`super()` /
  `Parent.method(self)` miss an override.~~ **Fixed** — each re-tested against
  the pinned compiler on 2026-08-19. What survived of them is listed above in
  its current, narrower form.
- ~~A **typed** constant in a Pascal unit reads as the zero value of its type in
  a Nil Python build.~~ **Fixed** — verified against the pinned compiler:
  `from reportlab.lib.units import mm` now yields `2.834645669291339`, and a
  typed `Double`/`Integer`/record constant reads its initializer whether the
  main program is Pascal or Nil Python.

If a real-world program hits one of these, check
[compatibility status](../reference/status.md) and the project's ticket board
before assuming it's a project-specific bug.
