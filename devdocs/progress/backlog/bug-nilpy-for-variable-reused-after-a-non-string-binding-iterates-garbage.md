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
everyday shape that hits this.

## How it was found

While writing the regression test for
[[bug-nilpy-char-vs-string-literal-ordering-compares-an-address]]: the same
classifier loop passed as a standalone program and failed inside the larger
file, because there the name `c` had already been used for `expr[j]` earlier.
That is worth noting on its own — the bug only appears when a file is long
enough to reuse a name, which is exactly when a human stops noticing.

## Cause (to confirm)

A NilPy name has one slot with one static type, widened across rebindings
(see [[bug-nilpy-int-prints-as-float-when-the-name-is-widened-later]] for the
same machinery producing `5.0` for `5`). A `for` variable is a VARIANT, but when
the name already exists with a scalar type the loop appears to store the
variant's payload into the old slot without converting — an int slot receives a
boxed pointer, a Char slot receives the low byte of one.

Confirm with `PXXDBG=n.locals` on the two failing shapes before fixing rather
than assuming; the widening story predicts a wrong VALUE, and the observed
`X`/`x` for a char slot looks more like a truncated pointer than a widened
character.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the table above
against CPython's own output. Include the fresh-name and prior-str rows as
guards, and re-run `test/test_nilpy_char_ordering.npy` with its loop variable
renamed back to `c` — that file documents the interaction and should stop
needing the workaround.
