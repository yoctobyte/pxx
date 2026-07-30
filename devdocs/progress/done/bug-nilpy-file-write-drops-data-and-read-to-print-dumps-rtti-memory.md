---
track: N
prio: 75
type: bug
---

# `f.write()` silently writes nothing, and once a "w" open exists, `print(f.read())` dumps RTTI MEMORY to stdout

```python
p = "/tmp/x.txt"
with open(p, "w") as f:
    f.write("hello\n")
with open(p, "r") as f:
    print(f.read())
```

CPython prints `hello`. pxx prints:

```
       TObject
       IInterface      \xd8Q     w @                   \xd8Q  ...
```

— the class-name table and RTTI blob from the program's own image, followed by
binary. Deterministic, reproduces on every run. And the file on disk is **0
bytes**: the `write` never happened either.

Two defects, both in the file-object model, and each reproduces alone.

## 1. `f.write()` writes nothing

```python
with open("/tmp/y.txt", "w") as f:
    f.write("abc")
```
The file is created and is zero length. No error, no exception. Any program
that produces output through the ordinary Python idiom silently loses all of it.

## 2. A "w" open in the program corrupts a later `read()` passed straight to `print`

The memory dump needs BOTH of:
- an `open(..., "w")` somewhere earlier in the program, and
- the `read()` result passed **directly** to `print`.

| form | result |
| --- | --- |
| `print(f.read())` after a "w" open | **RTTI blob** |
| `print(f.read().strip())` after a "w" open | **RTTI blob** |
| `print("[" + f.read().strip() + "]")` after a "w" open | `[]` (empty — bug 1, no dump) |
| `d = f.read()` then `print(d.strip())` after a "w" open | no dump |
| any of the above with NO "w" open in the program | correct |
| read-then-read of the same file, no "w" open | correct |

So concatenating the value, or routing it through a temp variable, hides it —
which is why ordinary tests miss this and why it looks intermittent.

## Likely cause

`open()` is not one function. The read-slurp model makes `open(p, "r")` yield
the file's LINES as a `TPyList` (that is what the `TPyList.read` method in
`pylib.pas` is for), while write mode needs a real handle — there is a
`TPyFile` class in the same unit. With both modes present, `open` resolves to
two different result types, and the value handed straight to `print` is
rendered as the wrong one: a file/RTTI pointer printed as text. The temp-var
and concatenation forms coerce through a string path first, which is why they
escape.

Consistent with the surrounding gaps: `f.close()` and `f.readlines()` report
`TPyList has no method close / readlines`, i.e. the read-mode object really is
a plain list.

## Why the priority is high

It prints process memory to stdout. That is a disclosure shape, not just a
wrong value — the dump contains class names and pointers, and its length is not
bounded by anything the program controls. Combined with defect 1, a program
that writes a report and reads it back produces neither the data nor an error.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` that writes a file,
reads it back and prints it in all four forms above, with CPython's own output
as the expectation — and an explicit check that the file on disk has the
expected byte length.

## ROOT CAUSE — measured, and the guess above was wrong

The "two `open` result types confuse `print`" theory in this ticket was wrong.
The real mechanism is a single overload miss, and it is worse than described:

`open(p, "w")` correctly returns a real `TPyFile` (parser.inc routes any
non-"r" mode to `pyfile_open`). `TPyFile` declared exactly one write:

```pascal
function write(b: TPyBytes): Int64;
```

so `f.write("hello\n")` — the ordinary Python spelling — resolved to it and
passed the **AnsiString's handle where a TPyBytes object was expected**. The
body then read `b.FData` as a buffer pointer and `b.FLen` as a length out of
whatever the string handle pointed at, and wrote THAT region to the file.

Before/after on the same program:

| | stdout | file size |
| --- | --- | --- |
| pinned (pre-fix) | the RTTI blob | **18 690 bytes** |
| fixed | `hello` | 6 bytes |

So it was not a print-time rendering problem at all: ~18 KB of adjacent process
memory was written INTO THE FILE and persisted, and printing it back is what
showed the class-name table. The earlier "writes 0 bytes" observations were the
same bug with a garbage length that happened to read as 0.

Fixed by declaring the text-mode overload `TPyFile.write(const s: AnsiString)`,
which writes `Length(s)` bytes from `@s[1]`. The bytes overload is unchanged.
Covered by `test/test_nilpy_file_write_text.npy`, whose expectations are
CPython's own output.

Remaining from this ticket, NOT fixed here: `f.close()` and `f.readlines()` on a
READ-mode handle still report `TPyList has no method ...`, because read mode
really does yield a list of lines. That is a separate shape and keeps this
ticket open.

## CLOSED — the two remaining causes, both found and fixed

1. **`close()`/`readlines()` missing on `TPyList`.** Added both:
   `close` is a no-op (the read-slurp model already holds the whole file), and
   `readlines` returns `Self`. Trivial once named.

2. **The real remaining disclosure vector, and it reproduces the RTTI blob
   independently of the write() overload above.** `PyAllocModuleGlobals`
   decides whether a module-level name was "used inside a routine before its
   own assignment" (the shape that needs pre-creating the symbol so an
   earlier-defined `def` can read it) by tracking generic INDENT/DEDENT
   depth — but a `with open(p, "w") as f: f.write(...)` block's suite indents
   exactly the same way a `def` body does. A later module-level
   `f = open(p, "r")` (SAME name reused, no `with` this time) made the scan
   see the with-block's own `f.write(...)` reference and conclude `f` was
   "used earlier", pre-creating `f` as a bare `tyVariant` symbol before the
   with-statement's real parse ever ran. `PyParseWith` then stored the raw
   `TPyFile` pointer straight into that unboxed variant slot (no boxing step),
   and every later use of `f` — `write`, `len`, `readlines` — dispatched
   against a variant whose "tag" was really just pointer bytes: write did
   nothing, and reading it back printed `0` or the class-name/RTTI blob
   depending on what got picked up. This is a SECOND, independent trigger for
   the exact disclosure shape the ticket is named for — no `TPyBytes`
   overload involved at all.

   Fixed by tracking which indent levels genuinely descend from a `def`
   header (a small per-level "inside a def" stack) instead of counting any
   indented block as "inside a routine".

Also needed, and correct standalone: two class-identity staleness bugs where
reassigning a name to a call returning a DIFFERENT class only updated the
stored RecName/RecCi if it had been unset before — so `f`'s identity from its
FIRST class stuck forever once anything had claimed it, even on an ordinary
rebind. Fixed to always take the latest class.

Tests: `test/test_nilpy_file_close_readlines.npy`,
`test/test_nilpy_with_name_reuse.npy`. Gate: `make test-nilpy` green,
self-host fixedpoint, `testmgr --tier quick` — all green.

Ticket closed.

## Log
- 2026-07-31 — resolved, commit 7a64a582d.
