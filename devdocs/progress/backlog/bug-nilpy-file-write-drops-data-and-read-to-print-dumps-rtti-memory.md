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
