---
prio: 50
track: N
type: bug
blocked-by: []
---

# A name bound in a block by a METHOD CALL is "undefined" in a later assignment

- **Type:** bug (NilPy, valid CPython refused) — **Track N**
- **Found:** 2026-08-09, writing a JSON round-trip program and diffing it
  against CPython.
- **Owner:** —

```python
with open(p) as f:
    raw = f.read()
n = len(raw)          # error: undefined variable (raw)
```

`print(len(raw))` on the very next line is **fine**. Only a bare assignment's
RHS is trial-parsed by the module pre-pass, and that asymmetry is what makes the
error impossible to place — the same name works one line earlier.

The shape is the most ordinary file read there is, and the same thing happens in
a `for` or `if` block, not just `with`.

## Cause

Same family as [[bug-nilpy-tuple-unpacked-name-undefined-in-a-later-assignment]]
and [[bug-nilpy-module-name-reassigned-from-a-subscript-in-a-block-reads-garbage]]:
`PyCollectModuleLocalsAST`'s depth>0 arm recognises a short list of safe RHS
token shapes, and a **method call** is not one of them, so the name is never
registered at all.

## ATTEMPTED AND REVERTED — the obvious fix is WRONG

Adding `name = other.m(...)` to the safe list, noting **tyVariant**, was
implemented, passed the repro and nine realistic programs — and then **regressed
`test_nilpy_none_str_field`**, caught by a whole-suite HEAD-vs-pinned sweep.

Why it breaks:

```python
tok = s.next_token()      # -> Optional[str], inside `while True:`
if tok is None: break
```

NilPy's `None` for a str-typed value is a **nil AnsiString handle**
(`pystr_is_none` tests `Pointer(s) = nil`). Widening `tok` to a variant changes
how `is None` is evaluated, the break never fires, and the loop runs away — the
exact failure `bug-nilpy-return-none-from-a-str-returning-def-yields-the-text-None`
exists to prevent, re-introduced from a different direction.

**So `tyVariant` is not a safe "widening" answer here.** It is safe for a
subscript (whose result genuinely is a variant) and for a tuple-unpack target
(likewise). It is NOT safe for an arbitrary call, whose result may be a str
whose None-ness lives in the string representation.

## What would actually work

Register the name **without asserting a type** — the goal is only that a later
trial parse can resolve it. That needs a way to declare a symbol the widening
table then leaves alone; `PyNoteLocalType` always contributes a type. Worth
checking whether `AllocVar(name, tyUnknown)` alone (no `PyNoteLocalType`) does
it, and what the widening harvest then does with an unknown.

The real close remains the one recorded on
[[feature-n-nilpy-ast-typing-module-scope]]: a pre-pass that does not
`Error()`-and-Halt on an as-yet-unseen name, which removes the safe-shape list
entirely and with it this whole family.

## Gate
The repro, plus `for`/`if` blocks, plus a JSON round trip — **and
`test_nilpy_none_str_field`**, which is the test that catches the tempting wrong
fix. Any change here wants the whole-suite HEAD-vs-pinned sweep, not a spot
check: nine realistic programs and the direct repro all passed the version that
was wrong.

## 2026-08-09 — the proposed route is CLOSED, and a worse sibling was found and fixed

### The route this ticket recommended does not work

"Register the name **without asserting a type** … worth checking whether
`AllocVar(name, tyUnknown)` alone does it." Implemented exactly that (no
`PyNoteLocalType`, so nothing reaches the widening table) and measured:

```
raw = f.read()  inside a block, then  n = len(raw)
  ->  pascal26: error: Variant := this type not yet supported
```

All three repro shapes (`with`, `for`, `Cls().m()`) fail the same way. A symbol
allocated as `tyUnknown` does not stay unknown — it is widened to Variant
downstream, and the real assignment then has no conversion. So the route trades
"undefined variable" for a different compile error, and does NOT reach the
type-free registration the ticket was after. Reverted.

That leaves the close recorded on [[feature-n-nilpy-ast-typing-module-scope]]
— a pre-pass that does not `Error()`-and-Halt on an as-yet-unseen name — as the
only route still standing. Worth raising this ticket's stake in that one rather
than trying a fourth shape here: three attempts (tyVariant, per-shape widening,
type-free registration) have now each been measured and each failed for a
different reason.

### A WORSE sibling, found while reproducing, and fixed

The reason the repro was written as `b = S().read()` is that it segfaulted the
*measurement*, not the compile:

```python
if True:
    k = Adder(4).describe()
print(k, len(k))
```

| | result |
| --- | --- |
| `pinned` | `error: undefined variable (k)` — loud |
| HEAD (before this) | prints the raw instance HANDLE, `len(k)` = **0** — silent |

The constructor arm added by `5d9d64e1b` (same day) recognises `name = Cls(...)`
from **two tokens** — an identifier naming a known class, and a `(` — without
checking they END the right-hand side. So a method call whose RECEIVER is a
construction was typed as the class. That is a **regression in kind**: a loud
compile error became a silent wrong value, which is the direction that matters.

Fixed by `PyBlkRhsEndsAfterCall`: scan to the matching `)` and require the next
token to end the statement. Scanning cannot `Error()`, so it respects the
constraint the whole branch works under. Exactly
`project_nilpy_constant_fastpath_claims_first_token_pattern` — a fast path
beside a real expression path is a second parser, and it disagrees quietly.

Test case added to `test_nilpy_block_nested_rebind_widens.npy` (the arm's own
test, rather than a near-duplicate file), with its three existing controls
confirming the narrowing did not undo the fix it guards: a plain
`b = Bare(1)` in a block still widens, and `test_nilpy_none_str_field` — the
canary for the tempting wrong fix — still passes.

**This ticket stays OPEN**: its own defect, `raw = f.read()`, is unchanged.
