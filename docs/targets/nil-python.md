---
title: Nil Python
order: 63
---

# Nil Python (`.npy`)

Nil Python is **python-ish**. It is a Python-shaped language that PXX compiles
ahead of time to native code, through the same backend as Pascal and C. It is
not a Python implementation and there is no interpreter at run time. A useful
core of everyday Python behaves as it does under CPython; outside that core,
Nil Python is **known to have plenty of issues**. If a program depends on
Python's dynamism, or on the standard library in depth, run it on CPython.

Source files may use `.npy` or `.py`; both go through the same frontend.

Every claim on this page was checked on 2026-09-24 by compiling a snippet
with the compiler at commit `8e68f024e2` (binary sha256 `b51d542b4e1f`) and,
where CPython can run the same source, comparing the output with CPython 3.14.4.

## Where it runs today

- **Desktop demos**: `examples/shell/` (a small shell, `nilsh`) and
  `examples/tk/` (GUI programs on PXX's `tkinter` facade). All twelve compile.
- **ESP32**: `examples/esp32/nilpy-*`, `adc-*`, `gpio-edge-*` and
  `monitor-s3`, for the ESP32-C3 (riscv32) and ESP32-S3 (xtensa). Each
  `main.npy` compiles to an object that ESP-IDF links; the chip runs that
  machine code, with no interpreter. All nine compile with pin v424
  (2026-09-25). `nilpy-s3`, `nilpy-hw-s3`, `gpio-edge-s3` and `adc-s3` ran on
  a physical ESP32-S3 board; `nilpy-c3` and `nilpy-hw-c3` ran under QEMU. The
  other three have only been compiled. Each directory's `build.sh` is the recipe, and
  [ESP32 peripherals](../library/esp.md) documents the units they import.
- **Linux cross targets**: i386, aarch64 and arm32 run Nil Python under QEMU,
  and wasm32 under wasmtime. riscv32 Linux refuses it at compile time.

## The core that works

These give CPython's output:

- **Functions**: with or without annotations, default values, `*args`,
  `**kwargs`, `lambda` closures, `global` and `nonlocal`.
- **Control flow**: `if`/`elif`/`else`, `while`, `for`, `break`/`continue`,
  `try`/`except (A, B) as e`/`finally`, `raise`, `assert`, `with`.
- **Comprehensions**: list, dict and set, with `if` filters.
- **Generators**: `yield` gives a lazy generator; a `for` loop over an infinite
  one that `break`s runs only as far as it consumed.
- **Classes**: single and multiple inheritance, `super()`, `@property` with
  `@x.setter`, `@staticmethod`, `@classmethod`, `@dataclass`, class
  attributes, attributes added to an instance after construction, and
  `getattr`/`setattr`/`hasattr`. Dunders dispatch, including `__init__`,
  `__str__`, `__repr__`, `__eq__`, `__add__`, `__len__`, `__getitem__`,
  `__call__`, `__enter__`/`__exit__`.
- **Values**: unannotated ints have arbitrary precision (`2 ** 100`); a
  variable rebound to a different type becomes a dynamic slot rather than an
  error; lists may hold mixed types.
- **Strings and containers**: the everyday methods of `str`, `bytes`, `list`,
  `tuple`, `dict` and `set`; slicing; unpacking; f-strings with `!r`/`!s` and
  format specs; `%` formatting and `str.format`.
- **Builtins**: `len`, `min`, `max`, `sum`, `abs`, `round`, `sorted`,
  `enumerate`, `zip`, `map`, `filter`, `any`, `all`, `isinstance`, `type`.
- **Catchable errors**: `int("abc")` raises `ValueError`, a bad index raises
  `IndexError`, a missing key raises `KeyError`.
- **Modules**: `math`, `re`, `json`, `random`, `collections.Counter`, `zlib`
  and others, each backed by a PXX unit (see [imports](#imports)).

## Known limits

Each of these was reproduced with the compiler named above.

| What you write | CPython | Nil Python |
| --- | --- | --- |
| `def f(n: int) -> int: return n * n`, then `f(2 ** 40)` | `1208925819614629174706176` | `0` — an `-> int` result is a 64-bit machine integer and wraps silently. Leave the return type unannotated to keep arbitrary precision. |
| `hex(2 ** 64 + 1)` | `0x10000000000000001` | `0x1` — hex, octal and binary text of an int wider than 64 bits is wrong; `format(x, "x")` on one raises `ValueError`. Decimal `str()` is correct. |
| inside a function, `b = len(sys.argv) - 1` (0 with no arguments), then `7 // b` inside `try/except ZeroDivisionError` | `caught` | `Runtime error 200`, exit code 200; the handler never runs. The same for a big int that reaches zero and for `divmod(7, b)`. Some shapes do raise and are caught (a literal `1 // 0`, a module-level `b = 0`, a zero divisor passed in as a parameter), so do not rely on the difference; test the divisor first. |
| `for v in (x * 2 for x in src()):` | lazy | the generator expression is evaluated in full before the loop starts |
| `a.nope()` where no class declares `nope` | `AttributeError` at run time | compile error: `A has no method nope` |
| `A.f = g` (replacing a method) | allowed | compile error; classes are fixed at compile time |
| `match x:` / `async def` | supported | compile error (`undefined variable (match)`) |
| `f"""a {v} b"""` | supported | compile error: triple-quoted f-strings are not supported |
| `import threading` | works | needs the `--threadsafe` compiler flag; the error says so |

A generator abandoned before it is exhausted, for example by `break`, does not
release the class instances held in its local variables.

## Where it differs on purpose

- **It is compiled.** Imports are resolved at compile time, so
  `sys.path.insert(...)` has no effect; use `-Fu` (below).
- **`__file__` names the executable**, not a source file, and so does
  `sys.executable`. Keep data files next to the binary and find them with
  `os.path.dirname(os.path.abspath(__file__))`.
- **`exec` and `eval` run a subset of Python** through a tree-walker, and only
  with an explicit namespace: `exec(src, d, d)`, `eval(src, g, l)`.
  `exec(src)` with no namespace is a compile error, because compiled locals
  have no run-time name table to bind into. The subset has no `import`, no
  `class`, and no nested `exec`.
- **It accepts some things CPython rejects**, such as the quoted import below.
  Nil Python is compatible with CPython in one direction only.

## ESP: math errors do not halt

On ESP targets the rule is that a math error must not stop the device. In the
owner's words, an embedded device *"should (try) to keep running, even if
whatever unexpected input (sensor etc) produces a math error. we should not
halt."* Desktop builds are unaffected.

On both ESP chips, `//` and `%` by zero give `0`, and `/` by zero gives an
IEEE infinity or NaN, with no `ZeroDivisionError`. That was checked with pin
v424 under QEMU on the ESP32-C3 and the ESP32-S3. On desktop targets Nil
Python raises `ZeroDivisionError` for all three, as CPython does. The full
table, with Pascal and C, is in
[Known issues](../reference/known-issues.md#by-design-math-errors).

## Imports

A bare `import name` means a Python module (`name.py` or `name.npy`), or one of
the PXX units that carry a Python surface, such as `math`, `re`, `json` or
`zlib`. To reach a Pascal or C file, quote it and give it an alias:

```python
import 'sysutils.pas' as su
print(su.Trim("  hi  "))          # hi
```

### Finding a third-party Python package: `-Fu`

`-Fu<dir>` adds a search root. Point it at the directory that **contains** the
package:

```sh
pxx -Fu/path/to/site-packages drv.npy drv
```

Without it, `from mypkg import greet` fails with
`import: no unit named mypkg and no shim mimic_mypkg`.

### Shims: standing in for a Python package

Some package names resolve to a PXX unit named `mimic_<module>` that implements
part of that package's API. The build says so:

```
note: reportlab_lib_pagesizes -> mimic_reportlab_lib_pagesizes (shim, subset)
```

A shim covers what PXX needed, not the package. `--no-shims` refuses every
substitution, so a build that passes with it contains no stand-in code.

### Python extension modules import bare

A Pascal unit that declares `{$PYEXTENSION}` and binds the cpyext runtime is a
Python extension module, the way `_json` is to CPython, so a bare `import`
reaches it. The declaration is required; binding the runtime alone does not
make a unit importable this way.

## C libraries

Nil Python can import a C header and call the library directly. A trailing
`T**` out-parameter becomes the return value, Python strings are passed as C
strings and `char*` results are copied back, and integer `#define`s become
constants.

A shim of the same name wins over a C header. `import sqlite3` therefore
reaches a small DB-API shim: `sqlite3.connect(...)` and `con.execute(...)`
work, but rows print as lists rather than tuples and `con.cursor()` does not
exist. Build with `--no-shims` to call SQLite's C API instead:

```python
import sqlite3                     # built with --no-shims
db = sqlite3_open("/tmp/users.db")
sqlite3_exec(db, "CREATE TABLE users(id INT, name TEXT);", 0, 0, 0)
```

That C route, with file-backed CRUD, is part of the test suite.

## Reporting a problem

Report it at <https://github.com/yoctobyte/pxx>. Include the smallest program
that shows it, CPython's output, PXX's output, and what `pxx --version` prints.
Expect gaps: a report is most useful when it comes from a real program rather
than a probe of an edge case.
