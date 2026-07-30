---
track: N
prio: 70
type: bug
---

# A `for` variable that was previously bound to a non-string value iterates GARBAGE

```python
c = 5
for c in "aZ":
    print(c)
# CPython: a / Z          pxx: 945815608 / 945815640     (addresses)

s = "x"
c = s[0]
for c in "aZ":
    print(c)
# CPython: a / Z          pxx: X / x                     (wrong characters)
```

Reusing a name as a loop variable is ordinary Python — the loop rebinds it — but
here the name keeps its EARLIER static type and the iteration writes through it,
so the loop yields values of the wrong type entirely.

## Boundary — MEASURED, and narrower than it first looked

The discriminator is the loop name's EXISTING scalar type versus the element
type, not "non-string" as this ticket first said. Full matrix:

| prior binding | iterating | pxx |
| --- | --- | --- |
| none (fresh name) | anything | correct ✓ |
| `c = "hello"` (str) | a string | correct ✓ |
| `c = None` | a string | correct ✓ |
| `c = s[0]` (char) | a LIST of str | correct ✓ |
| `c = 5` (int) | a LIST of int | correct ✓ |
| **`c = 5`** (int) | **a string** | **addresses** (`-379584456`) |
| **`c = 5`** (int) | **a list of str** | **TypeError: expected a number, got str** |
| **`c = 1.5`** (float) | **a string** | **`137307623522360.0`** |
| **`c = s[0]`** (char) | **a string** | **wrong chars** (`X`, `x`) |
| **`c = True`** (bool) | **a string** | **`True`, `True`** |

So: a name already bound to a NUMERIC or CHAR scalar, then reused as the loop
variable over STRING elements. The slot keeps its scalar type and the string
element's handle is stored into it — printed as an address, or rejected by the
coercion, exactly the "handle read as a number" family as
[[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]].

Reusing `i`, `n` or `x` as a loop variable after using it as a counter is the
everyday shape that hits this, and it is not hypothetical:

```python
n = 0
for n in ["a", "b"]:      # TypeError: expected a number, got str
    print(n)

i = 0
while i < 2:
    i = i + 1
for i in ["x", "y"]:      # TypeError
    print(i)
```

The REVERSE direction crashes outright:

```python
for c in "ab":
    pass
c = 5
print(c)                  # CPython: 5     pxx: SIGSEGV
```

so the conflict is symmetric — a slot typed by one side and written by the
other — not specific to the loop being second. A function PARAMETER reused as a
loop variable is fine (`def f(n): for n in [...]`), which is a useful clue: the
parameter's slot is already a variant.

Several of these now raise a TypeError rather than printing an address, which is
a side effect of the operand-coercion work
([[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]]) turning silent
handle-arithmetic into a diagnostic. The underlying slot conflict is unchanged.

## How it was found

While writing the regression test for
[[bug-nilpy-char-vs-string-literal-ordering-compares-an-address]]: the same
classifier loop passed as a standalone program and failed inside the larger
file, because there the name `c` had already been used for `expr[j]` earlier.
That is worth noting on its own — the bug only appears when a file is long
enough to reuse a name, which is exactly when a human stops noticing.

## ROOT CAUSE — one cause, three symptom clusters

Iterating a **string** types the loop variable `tyChar`, a SCALAR slot.
Iterating a **list** gives a variant. That single difference explains every row
measured:

| iterating | loop var slot | consequence |
| --- | --- | --- |
| a list | variant | any prior/later binding is fine — every list row above passes |
| a string | tyChar (scalar) | conflicts with any non-char binding, in either direction |

Confirmed by the reverse matrix:

| sequence | pxx |
| --- | --- |
| `for c in "ab"` then `c = "z"` (str) | correct ✓ |
| `for i in [1,2]` then `i = 5` | correct ✓ |
| `for w in ["a","b"]` then `w = 5` | correct ✓ — list iteration gives a variant |
| **`for c in "ab"` then `c = 5`** | **SIGSEGV** |
| **`for c in "ab"` then `c = 1.5`** | **SIGSEGV** |

and by the fact that a function PARAMETER reused as a loop variable is fine —
its slot is already a variant.

## The exact line, and TWO DEAD ENDS — do not retry either blind

`pyparser.inc`, `PyParseForIn`:

```pascal
  symIdx := PyProgSym(name);
  if symIdx < 0 then
  begin
    if enumMode then symIdx := AllocVar(name, tyInteger)
    else if isStr then symIdx := AllocVar(name, tyAnsiString)
    else symIdx := AllocVar(name, tyVariant);
  end;
```

The loop DOES pick the right type — but only for a NEW name. An existing name
keeps whatever slot it already had, and the loop stores string elements or
variant slots into it. That is the whole bug, in one `if`.

The obvious repair — re-type the existing symbol — was tried twice and reverted
both times, because a slot cannot be re-typed after it already holds a value of
the old type:

1. **Widen the existing slot to `tyVariant`.** Fixes every CONTAINER case
   (`n = 0` then `for n in ["a","b"]` starts working), but breaks string
   iteration: the desugar reads the loop variable's own slot type when storing
   each character, and a variant slot desynchronises the index/length
   bookkeeping — the loop yielded one element and then raised
   `IndexError: string index out of range`.
2. **Re-type to `tyAnsiString` for a string loop** (the kind a fresh name would
   get). Fixes the char-bound case, but an int-bound or float-bound name then
   SEGFAULTS: the earlier `c = 5` already wrote an 8-byte integer into that
   slot, and the string machinery now treats those bytes as a managed string
   handle and releases it.

Both failures are the same lesson: the earlier assignments have ALREADY been
emitted against the old type, so changing the symbol's type afterwards
corrupts what is in the slot. Retroactive re-typing is not available here.

## Fix — what it actually needs

Give the loop its own hidden slot of the correct type and ASSIGN the user's
name from it each iteration, so the user's name is rebound rather than
reinterpreted. The desugar already allocates hidden locals right above this
(`__py_c`, `__py_n`, `__py_i`), so the machinery is there; the loop variable is
the one that was left sharing the user's slot.

That also settles the reverse direction (`for c in "ab"` then `c = 5`, which
segfaults today) for free, since the user's name would carry a type that the
later assignment can widen normally.

Longer term this is the same `tyChar` overreach as That removes the scalar
slot the conflict needs, in both directions, and matches Python — where
iterating a str yields str objects of length 1, not a distinct character type.

This is the same `tyChar` overreach behind
[[bug-nilpy-char-vs-string-literal-ordering-compares-an-address]] and
[[bug-nilpy-subscript-and-slice-of-a-variant-get-the-wrong-static-type]]:
pxx has a character type and Python does not, and every place that lets
`tyChar` escape into a slot or a static type is a divergence. Worth considering
whether the three should be fixed together by not producing `tyChar` for NilPy
at all.

Watch the paths that currently depend on the char typing — `ord(c)`,
`c == "a"`, `chr()` round-trips and the digit-range comparisons — all covered by
`test/test_nilpy_char_ordering.npy` and `test/test_nilpy_variant_str_index.npy`.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the table above
against CPython's own output. Include the fresh-name and prior-str rows as
guards, and re-run `test/test_nilpy_char_ordering.npy` with its loop variable
renamed back to `c` — that file documents the interaction and should stop
needing the workaround.

## CLOSED

Root-caused to the type-inference PRE-PASS, not the loop desugar itself: the
loop DOES pick the right element type for a brand-new name (as the ticket's
"exact line" section already showed) — the bug was that the whole-program
widening table never learned a for-target's contributed type at all, because
`for` doesn't look anything like the `name = expr` shape the pre-pass's flat
scanner recognises. A name's FIRST creation (at either the scalar assignment
or the for-loop, whichever comes first in program order) then permanently
fixed a slot type the OTHER side later wrote through.

Fixed with three changes (see the commit for the full reasoning): `PyParseForIn`
now feeds its target name(s) into the same `PyNoteLocalType` table a bare
assignment feeds, whenever a typing pre-pass is running; the module-level
scanner gained a narrow, NON-PARSING peek at `for name in ITER:` headers (string
literal / list-or-set-literal / an already-typed name) that cannot itself
error out (`Error` halts the whole compiler, so actually trial-PARSING a
for-loop whose iterable depends on a `with`/`if`/`try`/class-body statement
the pre-pass doesn't otherwise enter was not safe — confirmed by two real
regressions this fix surfaced and fixed along the way,
`test_nilpy_sorted_pairs.npy`'s generator expression and
`test_nilpy_file_open.npy`'s `with`-block); and `PyParseForIn`'s real-pass
creation of a brand-new MODULE-level target now also consults the converged
table before deciding, closing the REVERSE-order case
(`for c in "ab": pass` before `c = 5`, previously a SIGSEGV).

`test/test_nilpy_char_ordering.npy`'s loop variable is renamed back to `c` as
the gate asked — output unchanged, confirmed against CPython.

Test: test/test_nilpy_for_variable_reuse.npy, the full matrix from this
ticket (every prior scalar binding x string-loop target, both orders) plus
the pre-existing container/parameter cases that must keep working. Gate:
make test-nilpy green, self-host fixedpoint, testmgr --tier quick.

Ticket closed.

## Log
- 2026-07-31 — resolved, commit 710a830e6.
