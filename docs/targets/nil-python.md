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
  machine code, with no interpreter. All thirteen `main.npy` projects under
  `examples/esp32/` compile with pin v445 (2026-09-27), with the flags their
  `build.sh` passes. `nilpy-s3`, `nilpy-hw-s3`, `gpio-edge-s3` and `adc-s3` ran on
  a physical ESP32-S3 board; `nilpy-c3` and `nilpy-hw-c3` ran under QEMU. The
  other seven have no recorded run; they are known to compile. Each directory's `build.sh` is the recipe, and
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

Each of these was reproduced with the compiler named above. On 2026-09-28
every row was checked again with pin v447 (compiler sha256 `fad87004e4e8`),
built for x86-64, i386 and arm32 (the last two run under QEMU), against
CPython 3.14.4: each row behaves as written, and the three targets print the same.

| What you write | CPython | Nil Python |
| --- | --- | --- |
| `def f(n: int) -> int: return n * n`, then `f(2 ** 40)` | `1208925819614629174706176` | `0` — an `-> int` result is a 64-bit machine integer and wraps silently. Leave the return type unannotated to keep arbitrary precision. |
| `hex(2 ** 64 + 1)` | `0x10000000000000001` | `0x1` — hex, octal and binary text of an int wider than 64 bits is wrong; `format(x, "x")` on one raises `ValueError`. Decimal `str()` is correct. |
| inside a function, `b = len(sys.argv) - 1` (0 with no arguments), then `7 // b` inside `try/except ZeroDivisionError` | `caught` | `Runtime error 200`, exit code 200; the handler never runs. The same for a big int that reaches zero and for `divmod(7, b)`. Some shapes do raise and are caught (a literal `1 // 0`, a module-level `b = 0`, a zero divisor passed in as a parameter), so do not rely on the difference; test the divisor first. |
| `for v in (x * 2 for x in src()):` | lazy | the generator expression is evaluated in full before the loop starts |
| `a.nope()` where no class declares `nope` | `AttributeError` at run time | compile error: `A has no method nope` |
| `A.f = g` (replacing a method) | allowed | compile error, because classes are fixed at compile time; the message, `cannot call non-static method on class type directly`, does not say so |
| `match x:` / `async def` | supported | compile error (`undefined variable (match)`) |
| `f"""a {v} b"""` | supported | compile error: triple-quoted f-strings are not supported |
| `import threading` | works | needs the `--threadsafe` compiler flag; the error says so |
| `def mk(): return gen(5)`, then `list(mk())`, where `gen` is a generator | `[5, 6]` | `[]` on every target (pin v446): a generator returned from a def yields nothing, and `next(mk())` does not compile. Create the generator where it is consumed. |
| on i386 or arm32, `exec` calling a method whose parameters are annotated (`name: str`, `n: int`, `flag: bool`) | works | crashes (pin v446); a method with unannotated parameters works |
| on arm32, `from time import sleep as pause`, then `pause(0)` | returns | never returns (pin v446); `from time import sleep` and `sleep(0)` work |

A generator abandoned before it is exhausted, for example by `break`, does not
release the class instances held in its local variables.

A Pascal `array of T` that a Pascal routine returns can only be indexed
straight off the call (`d.MakeArr(4)[3]`). After v448, binding it to a name,
`len()` of it and `for` over it are refused at compile time; with v448 and
earlier they compile and read wrong values. A Pascal `var` or `out` object
parameter needs a name that already holds an object. See
[Known issues](../reference/known-issues.md#fixed-since-v441) for what was
measured.

## Where it differs on purpose

- **It is compiled.** Imports are resolved at compile time, so
  `sys.path.insert(...)` has no effect; use `-Fu` (below).
- **`__file__` names the executable**, not a source file, and so does
  `sys.executable`. Keep data files next to the binary and find them with
  `os.path.dirname(os.path.abspath(__file__))`.
- **`exec` and `eval` run a subset of Python** through a tree-walker, with an
  explicit namespace: `exec(src, d, d)`, `eval(src, g, l)`. `exec(src)` with
  no namespace is a compile error, because compiled locals have no run-time
  name table to bind into. `eval(src)` with no namespace compiles, but sees
  none of the program's names: with pin v447, `n = len(sys.argv)` then
  `eval("n + 1")` stops with `pyeval: name not defined: n`, where CPython
  prints 2. The subset has no `import`, no
  `class`, and no nested `exec`.
- **It accepts some things CPython rejects**, such as the quoted import below.
  Nil Python is compatible with CPython in one direction only.

## Memory in Nil Python

**Reference counting, no collector.** Every object counts the names and
containers that refer to it, and it is freed the moment that count reaches
zero. There is no garbage collector running beside the program, so there are
no pauses, and memory comes back at a predictable point. On an ESP32 that is
what keeps a long-running program's heap flat.

**When memory comes back.** The table gives what was still allocated
(`live`) just before the function returned. The function filled a list with
30 strings and then let go of it in the way shown. Measured on x86-64 with
`tools/census_at_exit.sh`: pin v445 (`caf21ac399f1`) on 2026-09-27, and pin
v446 (`ae3466a018d8`) and the compiler after it (built at `e072d579b0`,
`ccd62c91f30e`) on 2026-09-28, and pin v448 (`b2b325036c3b`) and the compiler
after it (built at `a2614fcb8b`, `5dea028059af`) later that day:

| how the list was dropped | v445 | v446 | after v446 | v448 | after v448 |
| --- | ---: | ---: | ---: | ---: | ---: |
| kept (the control) | 32 | 32 | 32 | 32 | 32 |
| `kept = None` | 32 | 1 | 1 | 1 | 1 |
| `del kept` | 32 | 32 | 32 | 32 | 1 |
| a comprehension, then `rows = None` | 32 | 32 | 1 | 1 | 1 |
| at module level, `kept = None` | 32 | 1 | 1 | 1 | 1 |

- **With v445, dropping a name frees nothing until the function returns.** A
  list or dict that a statement creates is also held by a hidden temporary of
  that statement, so `kept = None` removes only one of two references. At
  module level it is held until the program ends.
- **From v446, each statement releases its temporaries when it ends**
  (`31d314dfa8`), so `kept = None`, `kept = 5` or a new `kept = []` frees the
  old list and everything in it at once. This applies at module level too.
- **`del name` and `name = None`.** Use `name = None`. With v445 neither frees
  a local before the function returns. From v446, `name = None` does, except
  on a list built by a comprehension, which v446 still holds until the
  function returns; that is fixed after v446 (`cdd6fd3c1f`, the table's fourth
  row). `del` on a local frees nothing until the function returns in v446 to
  v448 (the third row); that is fixed after v448 (`c4f5dcf929`, in no pin
  yet). On v448 and earlier, use `= None`, or return from the function to get
  that memory back.
- **Module-level temporaries.** A string built by a module-level statement,
  such as `print("n=" + str(n))` outside any function, is kept until that
  statement runs again. That is at most one string per source line and does not
  grow in a loop. Inside a function, temporaries are released when the
  statement ends.
- **A computed string on the left of `*`** (`str(i) * 2`, `"%d" % i * 2`,
  `s.upper() * 2`) leaks one string per evaluation with v445: 90 left after a
  90-pass loop. Fixed in v446 (`c64b304036`): with v446 (`ae3466a018d8`) each
  of the three leaves 1. On v445, name the string first
  (`t = str(i)` then `t * 2`), which left 1 instead of 30.

**Cycles are never freed.** Two objects that refer to each other
(`a.other = b; b.other = a`) keep each other's count above zero, and with no
collector nothing reclaims them. This is the design for this beta; CPython and
MicroPython both collect cycles. Break the cycle before letting go:

```python
class Node:
    def __init__(self):
        self.other = None

def pair():
    a = Node()
    b = Node()
    a.other = b
    b.other = a         # a cycle
    a.other = None      # break it before letting go
    a = None
    b = None            # both are freed

pair()
```

Measured with v445 and with the compiler after it: this program leaves
nothing allocated, and without the `a.other = None` line it leaves both nodes
(2 allocations).

**`gc` has nothing to collect.** From commit `c64b304036`, `import gc` runs
on the PC and compiles for the ESP32-C3 and the ESP32-S3; it has not been run
on an ESP32 for this page. It is library code, so the v445 pin compiles it from
such a tree. `gc.collect()` returns 0, and it does **not**
collect cycles. `gc.mem_free()` and `gc.mem_alloc()` report the heap:
ESP-IDF's byte-addressable heap on the ESP32, and PXX's own heap on a PC,
where `mem_free()` can be 0 in a small program. `enable()`, `disable()` and
`threshold()` change nothing, and `threshold()` returns -1. In a tree before
that commit, `import gc` does not build (`no member collect came of the
qualifier gc`); use `import 'espsys.pas' as sys` and `sys.free_heap()` on the
ESP32. Don't name your own file `gc.py` or `gc.npy`: it shadows the module.

### Measuring it

- **An exact count on the desktop.** Build with `-dPXX_ALLOC_CENSUS` and run
  it under `tools/census_at_exit.sh`. It prints `live=` (allocations not yet
  freed) at the moment the program exits. Call `sys.exit(0)` inside the
  function to count before it returns. Compare the number for one pass and for
  several: a leak grows with the passes, and a one-time cost does not.

  ```sh
  pxx -dPXX_ALLOC_CENSUS prog.npy prog
  tools/census_at_exit.sh ./prog
  ```

- **A bound in a test.** `tools/assert_no_leak.sh <label> <max-live>
  <command>` fails when a `-dPXX_ALLOC_CENSUS` program ends with more than
  `max-live` allocations live. It refuses a program that allocates too little
  to show anything (`too few to show anything`), so loop the code under test.
  Pair it with a version that leaks on purpose, to show that the check can
  fail.
- **On the ESP32, under QEMU.**
  `tools/esp_heap_soak_nilpy.sh --passes 20 nilpy-c3` runs an
  `examples/esp32` program's main loop repeatedly and prints the change in
  free heap per pass:
  `SOAK nilpy-c3 esp32c3 delta=0 passes=20 bpp=0` with v445. `--control` adds
  a deliberate 64-byte leak to each pass, to show that the soak sees one. Read
  the `SOAK` line, not the exit status.

## ESP: math errors do not halt

On ESP targets the rule is that a math error must not stop the device. In the
owner's words, an embedded device *"should (try) to keep running, even if
whatever unexpected input (sensor etc) produces a math error. we should not
halt."* Desktop builds are unaffected.

On both ESP chips, `//` and `%` by zero give `0`, and `/` by zero gives an
IEEE infinity or NaN, with no `ZeroDivisionError`. That was checked with pin
v445 on 2026-09-27 under QEMU on the ESP32-C3 and the ESP32-S3: `print(a // b,
a % b)` and `print(x / y, y / y)` with `b = 0` and `y = 0.0` printed `0 0` and
`inf nan`, and the program carried on. On desktop targets `/` by
zero raises `ZeroDivisionError`, as CPython does, and so do `//` and `%` in
most shapes; some shapes stop with runtime error 200 instead (see
[Known limits](#known-limits)). The full
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
