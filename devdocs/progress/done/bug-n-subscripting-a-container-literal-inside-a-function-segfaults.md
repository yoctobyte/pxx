---
track: N
prio: 65
type: bug
blocked-by: []
summary: "`return (a, b)[i]` inside a function or method segfaults at runtime, no diagnostic. Both tuple and list literals; constant or variable index; constant or variable contents — all crash. The SAME expression at module level works, binding the literal to a local first works, and subscripting a string literal works. Found writing lib/rtl/mimic_urllib_parse.py, where a ParseResult's __getitem__ is exactly this shape."
status: done
owner: frank2-7e
---

# Subscripting a container literal inside a function segfaults

- **Type:** bug — **Track N** (Nil-Python frontend / lowering).
- **Found:** 2026-08-18 by frank3-fc, writing `ParseResult.__getitem__` for
  [[feature-b-mimic-six-moves-needs-http-client-and-urllib]].
- **Measured against:** `pinned` **v351** (`e4ca45a1819c`, pin `a6d6dfb84`).
- CPython accepts and runs every line below.

## Repro

```python
def f():
    return (1, 2)[0]

print(f())      # Segmentation fault -- CPython prints 1
```

Compiles clean. No warning, no note.

## The boundary — crossed, not walked

| shape | result |
| --- | --- |
| **function: `(1, 2)[0]`** — constants, constant index | **SEGFAULT** |
| **function: `(a, b)[i]`** — locals, variable index | **SEGFAULT** |
| **function: `[a, "y"][0]`** — a LIST literal | **SEGFAULT** |
| **method: `(self.a, "y")[0]`** | **SEGFAULT** |
| function: `t = (a, "y")` then `t[0]` | ✅ |
| function: `"xy"[0]` — a STRING literal | ✅ |
| module level: `(1, 2)[0]` | ✅ |
| module level: `(a, "y")[i]` | ✅ |

So neither the contents nor the index kind matters, and it is not tuples
specifically — it is **subscripting a container literal in a function body**.
Binding it to a local first is correct, and the same expression at module level
is correct.

The axes were crossed rather than walked, after
`devdocs/dev/debugging-playbook.md`: contents (constant / variable), index
(constant / variable), container (tuple / list / str), and site (module /
function / method). Only the last one, plus literal-vs-bound, predicts the
crash.

Reading, not a measurement: a literal in a function body appears to be built
somewhere that does not survive being subscripted in place — a temporary whose
lifetime ends before the index, or one that is never materialised at all.

## Why it matters

`(x, y)[i]` is how Python spells a small lookup table, and the idiom is
everywhere: `__getitem__` over a fixed field list, `("no", "yes")[flag]`,
selecting from a literal of branches. It is a crash rather than a wrong value,
so it fails loudly — but it fails at RUNTIME with no compile-time hint, in code
that reads as ordinary Python.

## Track B site

`lib/rtl/mimic_urllib_parse.py` — `SplitResult.__getitem__` and
`ParseResult.__getitem__` bind the field tuple to a local before indexing it
instead of `return (self.scheme, ...)[i]`. Registered in
`devdocs/dev/track-b-workarounds.md`; revert when this lands.

## RESOLVED 2026-08-18 (frank2-7e, Track N) — the axis was the return-type SCAN, not the subscript

Reproduced at HEAD (not on the pinned v351 the ticket measured against) and
root-caused by measurement.

### The subscript is innocent — it is the RETURN

The ticket's boundary table is right about every row and the reading under it
("a temporary whose lifetime ends before the index") is not. One row it did not
cross settles it:

| shape | result |
| --- | --- |
| `def f(): print((1, 2)[0])` — subscript a literal, do not return it | ✅ works |
| `def f(): x = (1, 2)[0]; return x` | SEGFAULT |
| `def f(): return len((1, 2))` — literal, non-class result | ✅ works |
| `def f(): return [1, 2, 1].count(1)` — literal, METHOD, not a subscript | SEGFAULT |

So subscripting a literal in a function body is fine; **returning anything
derived from one** is not, and it is not specific to subscripts.

`gdb` + the `.map` put the fault at `pylist_repr+0x1e0` — `print` was handed a
LIST, walked it, and died. Confirmed independently: `print(len(f()))` on
`return [10, 20, 30][1]` also crashes, i.e. the value coming back really is the
container, not the element.

### Root cause

`PyInferDefRetType` types a `return` from a TOKEN SCAN, and the two literal arms
at the top of `PyInferExprType` answered the literal's own class and **`Exit`ed
on the opening bracket**, ignoring every token after the literal closes. So
`return (1, 2)[0]` registered a `tyClass`/TPyList result: the element VARIANT was
stored into a class result slot, the caller read it as an object handle, and the
frame that owned the literal was gone by the time anyone dereferenced it.

`PXXDBG=a.ir:f` shows it directly — `store_sym 409 [$pyresult] tk=6`, tk 6 being
`tyClass`.

### Why literal-vs-bound was the only predictive axis

Because the "a subscript yields a VARIANT" rule already exists — it has since
`bug-nilpy-subscript-and-slice-of-a-variant-get-the-wrong-static-type` — but it
lives in the arm that handles `name[...]`, keyed to an **IDENT** receiver. A
literal receiver never reaches it. `t = (1, 2)` then `t[0]` works for exactly
that reason, and module level has no return type to infer at all.

That is the sibling case `devdocs/dev/normalise-dont-special-case.md` is about:
one concept reachable through two shapes, with the second shape left broken.

### The fix

`PyLiteralPostfixType` (new, `pyparser.inc`): before either literal arm exits,
ask what POSTFIX follows the literal's closing bracket.

- subscript (non-slice) -> `tyVariant`
- `.method(...)` on a literal -> `tyVariant` (the answer this scan already gives
  for a call it cannot type)
- a SLICE -> unchanged, a slice yields the container
- nothing, or an operator (`[1, 2] + [3]`) -> unchanged, the literal's class is
  the right answer

Written as "the literal is not always the whole expression" rather than as a
subscript special case, which is why the `.count(1)` row — never in the ticket —
is fixed by the same three lines.

### Verified

Every crashing row in the table above, plus the LUT idiom `("no", "yes")[flag]`,
the method form `(self.a, "y")[i]`, a dict literal `{"a": 1}["b"]`, and nested
`[[1, 2], [3, 4]][1][0]` — all match CPython. The neighbours that must NOT move
were crossed too: slice-of-literal, a bare literal return, and a literal operand.

Swept the class rather than stopping at the ticket: a local typed from a literal
subscript, a module-level one, a FIELD initialised from one, a literal subscript
passed as an argument, and `{"a": 1}.get("a")` — all correct, so there is no
second site to fix.

**Track B site is unblocked and I did not touch it** (not my lane). The platonic
`return (self.scheme, self.netloc, self.path)[i]` now runs correctly — verified
with the real `ParseResult` shape — so `lib/rtl/mimic_urllib_parse.py` can drop
its bound-local workaround and the row can come out of
`devdocs/dev/track-b-workarounds.md`. That revert is Track B's to make.

**Test:** `test/test_nilpy_subscript_container_literal.npy`, wired into BOTH
`test-nilpy` and `test-core` (the anchor appears twice; a test wired into only
one of them is uncovered).

**Gate:** `make compiler/pascal26` fixedpoint (converged after 1 round) +
`tools/gate.sh quick` GREEN.

## Log
- 2026-08-18 — resolved, commit PENDING-COMMIT.
